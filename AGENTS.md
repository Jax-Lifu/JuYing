# 聚映 (JuYing) Android 原生工程约束与指导原则

> **项目定位**：面向 **Android TV / 机顶盒（10-Foot UI）**、**平板** 与 **手机** 的高性能全源聚合播放器，最低支持 **Android 9 (`minSdk 28`)**，对 **1–4GB 内存 / 低功耗芯片（如 RK3568、S905、H618）** 做一等公民级别的深度优化。开源协议：**GPL-3.0**。

---

## 1. 核心工程原则

1. **低配设备与 TV 性能优先 (Low-Spec & TV First)**：
   - **启动零阻塞**：`JuyingApplication.onCreate` 严禁执行任何 I/O、数据库初始化、网络请求或爬虫预热；Room、OkHttp、DataSource、Spider 与 ExoPlayer 实例一律通过 Hilt 懒加载。
   - **硬件档位自适应 (`DeviceProfile.tier`)**：由 `DeviceProfileDetector` 根据 `isLowRamDevice` 与物理内存划分 `LOW` (<2.3GB) / `MID` (<4.6GB) / `HIGH` 三档，统一驱动 OkHttp 缓存与并发上限、ExoPlayer `DefaultLoadControl` 缓冲字节阈值（`LOW` 档严格限制为 24MB）以及动效降级开关。
   - **零拷贝视频直出 (Zero-Copy Hardware Overlay)**：视频渲染强制使用原生 `SurfaceView` 绑定 `Media3 (ExoPlayer)`，走系统 Hardware Composer (HWC) 独立硬件平面送显，支持 4K、HDR10、杜比视界 (Dolby Vision) 与杜比音频直通，严禁默认使用 `TextureView` 或跨层 GPU 纹理拷贝。
   - **纯原生 View 体系**：采用 `Fragment` + `ViewBinding` + `RecyclerView (DiffUtil)`，**不使用 Jetpack Compose**，不使用实时毛玻璃 (`RenderEffect` / `BlurMaskFilter`)。低配机列表默认关闭 `itemAnimator`，进度条仅在控制栏可见且处于前台时以 1s 间隔低频轮询，严禁将高频播放进度塞入全局 `StateFlow`。
   - **单播放器实例铁律**：全局最多存活一个 `PlayerEngine`（由 `PlaybackManager` 管控），退出 `PlayerActivity` 时在 `onCleared()` 立即 `release()` 释放 MediaCodec 硬件解码器与缓冲内存。

2. **一套代码适配三端形态 (TV / Tablet / Phone)**：
   - 单 Activity 壳 (`MainActivity` + Navigation) 配合独立 `PlayerActivity`。
   - 布局按资源限定符分流：`layout/`（手机底部导航栏）、`layout-sw600dp/`（平板侧边导航栏）、`layout-television/`（电视侧边栏 + D-Pad 焦点优先），尺寸与列数统一走 `values-*` (`dimens.xml` / `integers.xml`)。
   - 所有可交互控件必须支持 TV 遥控器方向键 (`DPAD_UP/DOWN/LEFT/RIGHT/CENTER/ENTER/MENU/BACK`) 与焦点高亮状态 (`bg_item_focusable`)。

3. **内容与应用解耦**：
   - 应用自身**严禁内置、分发或运营任何第三方盗版媒体源**；仅提供央视 (`CCTV`) 官方公开入口与本机/局域网自动发现能力，其余订阅源与网盘挂载均由用户自行配置。

4. **提交信息规范**：
   - 提交信息前缀统一使用 `feat / fix / refactor / perf / docs / test / chore`，例如 `feat(source): 统一多源能力契约与动态源发现机制`。

---

## 2. 模块化架构与严格依赖边界

工程参考 Google *Now in Android* 模块化设计，但 UI 层全面采用轻量级原生 View：

```text
app                 ──► 组装全模块、提供 Navigator 跨页路由实现
feature:*           ──► 仅依赖 core:* 与 player:api（严禁依赖其他 feature:*、source:*、player:media3）
core:domain         ──► 跨 Repository 组合用例（GetPlayItemUseCase、ZapChannelUseCase）
core:data           ──► Repository 实现 + SourceRegistry（通过 Hilt @IntoSet / @IntoMap 汇总源与协议）
source:api          ──► 统一数据源契约（SourceProvider / LiveSource / VodSource / BrowseSource / SourceDiscoveryProvider）
source:*            ──► 各具体数据源实现（cctv / iptv / tvbox / smb / webdav / alist / cloud / local / usb / upnp ...）
player:api / media3 ──► 播放内核抽象与 Media3 实现（JuyingDataSourceFactory 按 URI scheme 路由自定义协议）
core:model          ──► 纯 Kotlin 领域模型（零 Android 依赖，可纯 JVM 单测）
```

- **构建期强制校验**：`AndroidFeatureConventionPlugin` 在 Gradle `afterEvaluate` 阶段强制检查依赖图，任何 `feature:*` 若直接依赖其他 `feature`、`source:*` 或 `player:media3` 会直接阻断构建。
- **跨页面跳转**：一律通过 `core:ui` 中的 `Navigator` 接口触发。

---

## 3. 多源统一架构规范 (Unified Multi-Source Architecture)

框架从初期即统一抽象以下 **11 类数据源 (`SourceType`)**，杜绝在业务层或 UI 层写死 `if (type == ...)` 分支：

| 类别 | `SourceType` | 核心能力 (`SourceCapability`) | 产生方式 | 播放传输链路 (`URI Scheme`) |
| :--- | :--- | :--- | :--- | :--- |
| **央视官方** | `CCTV` | `LIVE`, `VOD`, `SEARCH` | 内置 (`SourceDiscoveryProvider`) | `http(s)://`（动态鉴权 HLS） |
| **TVBox 聚合** | `TVBOX` | `LIVE`, `VOD`, `SEARCH` | 用户配置（单仓/多仓 URL 或本地文件） | `http(s)://`（支持多子站 `SubSource` 与请求头注入） |
| **IPTV 直播** | `IPTV` | `LIVE`, `SEARCH` | 用户配置（M3U/M3U8/TXT 订阅或本地文件） | `http(s)://`, `rtsp://`, `rtp://`, `udp://` |
| **网盘直连/聚合** | `CLOUD_DRIVE` | `BROWSE`, `VOD`, `SEARCH` | 用户配置（夸克/阿里/百度/115 等，参数存 `extra`） | `http(s)://`（带 Cookie/Header/302 重定向） |
| **Alist 挂载** | `ALIST` | `BROWSE`, `SEARCH` | 用户配置（Alist 地址 + 令牌/密码） | `http(s)://`（302 直链或代理流） |
| **WebDAV** | `WEBDAV` | `BROWSE` | 用户配置（WebDAV 地址 + Basic/Digest 凭据） | `http(s)://`（带 Authorization Range 请求） |
| **局域网 Samba** | `SMB` | `BROWSE` | 用户配置（`smb://host/share[/dir]`） | `smb://`（`SmbDataSourceFactory` 随机读取） |
| **局域网 NFS** | `NFS` | `BROWSE` | 用户配置（`nfs://host/export[/dir]`） | `nfs://`（自定义 `DataSource.Factory`） |
| **本机存储** | `LOCAL` | `BROWSE` | 动态发现 / SAF 授权目录 | `file://`, `content://` |
| **移动存储 (U盘/硬盘)** | `USB_STORAGE` | `BROWSE` | 动态发现（监听 `StorageManager` / USB 挂载广播） | `file://`, `content://` |
| **局域网 UPnP/DLNA** | `UPNP` | `BROWSE`, `SEARCH` | 动态发现（SSDP 发现局域网 DMS `ContentDirectory`） | `http://`（DMS 媒体直链） |

### 多源统一的 5 条设计铁律

1. **能力接口正交组合 (`SourceProvider`)**：
   - 任何数据源模块只需按自身能力实现 `LiveSource`、`VodSource`、`BrowseSource`、`SearchableSource` 中的一个或多个，并通过 Hilt `@Binds @IntoSet abstract fun bindSource(impl: XxxSource): SourceProvider` 注册。
   - **严禁在 ViewModel/Fragment 中硬编码 `SourceType` 列表**；查询可用源一律通过 `SourceRepository.observeSources(capability: SourceCapability)` 或 `SourceRegistry`。
2. **静态配置与动态发现合流 (`SourceConfig` + `SourceDiscoveryProvider`)**：
   - 用户手动添加的源存储在 Room `sources` 表中，各协议特有参数（如 TVBox 的 `repoUrl`/`siteKey`、网盘的 `driveType`/`refreshToken`、SMB 的 `domain`、IPTV 的 `epgUrl`/`userAgent`）统一存入 `SourceConfig.extra: Map<String, String>`（数据库序列化为 JSON），避免频繁修改表结构。
   - 免配置或热插拔数据源（内置 `CCTV`、`LOCAL` 本机目录、`USB_STORAGE` 外接 U 盘、`UPNP` 局域网媒体服务器）通过实现 `SourceDiscoveryProvider`（`@IntoSet`）实时发出 `Flow<List<SourceConfig>>`，由 `DefaultSourceRepository` 与数据库源自动合并。
3. **复合源的子源/子站点穿透 (`SubSource`)**：
   - 针对 `TVBOX`（单仓内含几十个 Spider 站点）或 `CLOUD_DRIVE`（多盘挂载）等复合源，通过 `VodSource.subSources(config)` 暴露子站点列表，`VodCategory` / `VodItem` / `PlayRequest` 通过 `ref`（或 `extra`）透传子站点路由，对上层 UI 保持统一的 `VodRepository` 接口。
4. **多线路与请求头一等公民支持 (`PlayLine` + `PlayItem`)**：
   - 直播频道 (`Channel`) 与播放项 (`PlayItem`) 原生支持多条候选线路 (`PlayLine(url, label, headers)`)。
   - `PlayerViewModel` 在主线路播放报错时，自动按 `PlayItem.backupLines` 顺序无感切换备用线路；`JuyingDataSourceFactory` 在每次打开流时动态注入当前线路的自定义请求头（`User-Agent`、`Referer`、`Origin`、`Cookie`、`Authorization`）。
5. **目录浏览源的同目录外挂字幕自动挂载 (`SidecarSubtitles`)**：
   - 所有实现 `BrowseSource` 的数据源（`SMB`、`WEBDAV`、`NFS`、`ALIST`、`CLOUD_DRIVE`、`LOCAL`、`USB_STORAGE`、`UPNP`）在生成 `PlayItem` 时，统一通过 `SidecarSubtitles.matchFor(videoEntry, siblings)` 自动匹配同目录下同名 `.srt` / `.ass` / `.ssa` / `.vtt` 字幕并挂入 `PlayItem.subtitles`。

---

## 4. Grill Mode（需求拷问模式）

- 当用户明确说出 `grill me` 时，不得立即开始编写功能代码。
- 积极且建设性地挑战现有假设，识别含糊、不完整或相互冲突的需求。
- 针对低配 TV 盒子的内存/CPU 预算、遥控器焦点可达性、多源协议边界与异常回退策略提出尖锐问题。
- 每次只提出一个影响最大的关键问题，等待用户回答后再继续追问，直至消除不确定性并输出可执行计划。

---

## 5. 代码注释与代码风格规范

1. **工程师级注释（Why + What）**：
   - 公开契约（`core:model`、`source:api`、`player:api`）、性能降级阈值、自定义 `DataSource` 状态流转与并发保护必须编写清晰注释。
   - **What**：简明说明对外契约、参数约定与边界行为。
   - **Why**：阐明架构取舍（尤其是针对低端机顶盒内存/解码器怪癖、协议坑点的设计原因），严禁编写翻译语法的机械式废话注释。
2. **代码风格（Kotlin Official）与统一日志规范（Timber）**：
   - 遵循 `kotlin.code.style=official`（4 空格缩进，UTF-8，LF 换行，末尾单空行）。
   - **默认日志统一使用 `Timber`**：`juying.android.application` 与 `juying.android.library` 约定插件已默认引入 `com.jakewharton.timber:timber`，并在 `JuyingApplication.onCreate()` 按需挂载 `Timber.DebugTree()`。业务与基础设施模块一律使用 `Timber.d / i / w / e` 打印结构化日志，严禁直接调用 `android.util.Log` 或 `println`，且严禁在日志中输出明文密码、Cookie 或 Token。
   - 保持极简：不写无用的包装类，单实现不强拆接口（跨模块边界如 `source:api`、`player:api`、`core:data` 除外）。
3. **明确类型与命名常量**：
   - 有限的业务状态、协议类型与操作使用 `enum class` / `sealed interface`；复合路由、子站引用和运行时请求使用明确的 `data class`，避免散落字符串拼接与整数分支。
   - 超时、分页大小、并发和内存上限使用带单位及含义的命名常量；第三方协议字段、分隔符和数值编码集中在对应适配器边界转换，不泄漏到 ViewModel / Fragment。
   - 优先复用现有模型与契约，不为普通文案、自然的 0/1 运算或单次字段读取建立无意义包装。新增解析、路由和状态分支同时覆盖边界、取消与失败测试。

---

## 6. 编译与真机测试规范 (`qytech6666`)

- **首选测试设备**：`qytech6666`（MX5 / RK3568，Android 12 / API 32，arm64-v8a）。
- **常用验证命令**：
  ```powershell
  # 1. 运行纯 JVM 与 Android 单元测试（解析器、多源注册表、配置与模型）
  .\gradlew.bat testDebugUnitTest :core:model:test :source:api:test

  # 2. 编译并安装 Debug 包到 qytech6666
  .\gradlew.bat :app:installDebug

  # 3. 在 qytech6666 真机上运行 Instrumentation 测试
  $env:ANDROID_SERIAL="qytech6666"; .\gradlew.bat :app:connectedDebugAndroidTest
  ```
