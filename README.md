# 聚映 (JuYing) — Android 端

面向 **Android TV / 平板 / 手机** 的高性能全源聚合播放器。最低支持 Android 9 (`minSdk 28`)，开源协议 GPL-3.0。
深度针对 **1–4GB 内存 / 低功耗芯片** 进行低延迟与低内存优化，提供全原生 View 与硬件直出播放体验。

## 核心特性

- **多媒体源聚合**：
  - **央视 (CCTV)**：官方栏目分类与专辑选集，默认采用官方 H5E / CDRM 高清原生流直出，支持完整进度拖动与多档位清晰度切换，拒绝 WebView 回退。
  - **TVBox 生态**：兼容 CMS XML/JSON（type 0/1）、Jar（DEX/Init/safeDns）、QuickJS 模块与 CPython 3.11 爬虫，支持 Base64 与 2423 CBC 加密配置及中文域名；脚本独立进程隔离运行。预置「金牌 · 肥猫」「急救 · 肥猫」两个入口，允许编辑、停用或删除，删除后重启不恢复；其他订阅由用户自行配置。
  - **IPTV 直播**：支持网络订阅与本地 M3U/TXT 导入、可用性检查、XMLTV (gzip) 节目单流式解析与故障自动换线。
  - **局域网与本地媒体**：原生集成 Samba (SMB) 与本机/移动存储目录导航，智能关联同目录外挂字幕，播放退出保留浏览位置。
- **三端形态适配**：
  - 电视端：大尺寸按键、全界面 D-Pad 遥控器方向键导航与清晰的焦点高亮状态。
  - 平板与手机端：平板侧边栏分栏布局，手机底部导航与竖屏分行自适应控制栏。
- **低配性能调优**：
  - 启动零阻塞：数据库、网络、爬虫解释器与播放引擎按需懒加载。
  - 视口预取：列表滚动提前加载下一页与下一屏封面，连续滑动不丢帧；RecyclerView 局部刷新（Payload）优化焦点变化。
  - 单播放器生命周期：全局只保留一个 `PlayerEngine`，离开播放页立即释放 MediaCodec 与缓冲内存。
  - 硬件直显：SurfaceView 绑定 Media3，避免纹理跨层拷贝，支持 4K/HDR 高规格渲染。

## 首次构建

1. 安装 JDK 17、Android SDK 36。运行环境一键初始化脚本（若未安装 uv 将自动下载安装并创建项目专属 Python 3.11 `.venv`）：
   ```powershell
   .\scripts\setup_env.ps1
   ```
   > 注：若直接执行 `.\scripts\build_apk.ps1`，脚本也会在首次编译时自动检测并完成环境初始化。
2. 用 Android Studio 打开本工程，或运行仓库根目录的 `gradlew.bat`；依赖版本统一在 `gradle/libs.versions.toml` 管理。
3. 单元测试与构建：
   ```powershell
   .\gradlew.bat testDebugUnitTest :core:model:test :source:api:test
   .\gradlew.bat :app:assembleDebug
   ```
4. 运行设备测试（需至少一台处于 `device` 状态的 Android 设备）：
   ```powershell
   adb devices
   # 多设备时可选设置: $env:ANDROID_SERIAL = "<设备序列号>"
   .\gradlew.bat :app:connectedDebugAndroidTest
   ```

> **注意**：Windows 环境下若遇到 JDK Unix domain socket 路径长度限制，可将当前终端的 `TEMP`、`TMP` 设置为短路径后重试。

Release 构建必须配置 `JUYING_KEYSTORE_PATH`、`JUYING_KEYSTORE_PASSWORD`、`JUYING_KEY_ALIAS`、`JUYING_KEY_PASSWORD` 环境变量；缺少时构建失败，不会改用 debug 签名。签名文件保存在仓库外，并持续使用同一密钥。GitHub 发布还需设置 `JUYING_KEYSTORE_BASE64` Secret 及上述三个密码/别名 Secret，工作流会临时还原并清理签名文件。

版本默认是 `0.0.2`，可通过 `-PappVersion=主版本.次版本.补丁版本` 指定；每段为 0–999，`versionCode = 主版本 × 1000000 + 次版本 × 1000 + 补丁版本`，发新版必须提升版本号。标签发布使用标签中的版本（可带 `v` 前缀），保留现有 APK 命名格式。发布前运行单元测试和 Debug 构建；Windows 安装脚本回归使用 `python scripts/tests/test_run.py`。安装冲突会停止并保留旧应用数据，不会自动卸载。

编译脚本默认按架构生成三类 APK；未指定构建类型时编译 Debug 和 Release，Release 仍需上述签名配置：

| 文件后缀 | 包含架构 |
|---|---|
| `_universal.apk` | `arm64-v8a` + `armeabi-v7a` |
| `_arm64-v8a.apk` | ARM64 |
| `_armeabi-v7a.apk` | ARMv7（32 位） |

```powershell
.\scripts\build_apk.ps1 -Debug                 # 三类 Debug 包
.\scripts\build_apk.bat --debug                # 同上
./scripts/build_apk.sh --debug                 # Linux / macOS / Git Bash
.\scripts\build_apk.ps1 -Debug -Abi universal  # 仅通用包
.\scripts\build_apk.bat --debug --abi arm64-v8a
./scripts/build_apk.sh --debug --abi armeabi-v7a
.\gradlew.bat :app:assembleDebug -PtargetAbi=arm64-v8a
```

三个编译脚本均支持 `all`（默认）、`universal`、`arm64-v8a`、`armeabi-v7a`；PowerShell 使用 `-Abi`，Batch/Bash 使用 `--abi`。直接运行 Gradle 时省略 `targetAbi` 只构建通用包。APK 与 Release mapping 以相同架构后缀归档到原有 `dist/` 目录，`--clean` / `-Clean` 只在第一轮执行。

GitHub 发布工作流先运行测试和 Debug 构建，再生成三类签名 Release 包。Actions 产物按 `JuYing-Release-<架构>` 分组，标签 Release 附带全部三类 APK 及各自 mapping。`run.bat`、`run.ps1`、`run.sh` 默认只选择通用包，跳过编译时也不会误选单架构包。编译脚本回归使用 `python scripts/tests/test_build_apk.py` 和 `python scripts/tests/test_build_apk_shells.py`。

## 架构设计

基于模块化分层架构（参考 Now in Android 原则，UI 采用纯原生 View 体系）：

```text
UI 层      Fragment / PlayerActivity ← ViewModel (StateFlow<UiState>)
Domain 层  UseCase（跨 Repository 聚合业务时引入）
Data 层    Repository（单向数据流 Flow） → SourceRegistry → 具体 source:* 模块
```

- **三端资源分流**：一套代码适配多端形态：`layout/`（手机）、`layout-sw600dp/`（平板）、`layout-television/`（电视）；尺寸与间距统一由 `values-*` 分流。
- **模块依赖铁律**：`feature:*` 之间禁止互相依赖，禁止直接依赖 `source:*` 具体实现或 `player:media3`；页面间跳转与源选择统一通过 `core:ui` 的 `Navigator`。

## 模块划分

| 模块 | 职责定位 |
|---|---|
| `app` | 入口组装、全局 Navigation 图、`Navigator` 实现与 Hilt 依赖图装配 |
| `core:model` | 纯 Kotlin 领域模型，无 Android 框架依赖 |
| `core:common` | 协程调度器注入、`DeviceProfile`（形态与 LOW/MID/HIGH 性能档位策略） |
| `core:network` | OkHttp 配置（按性能档位动态配置缓存与并发）、网络请求工具 |
| `core:database` / `core:datastore` | Room 持久化（播放源、播放历史、收藏）与 DataStore 设置 |
| `core:data` | 统一 Repository 体系与 `SourceRegistry`（多重绑定自动收集数据源） |
| `core:domain` | 跨模块用例（如 `GetPlayItemUseCase`、`ZapChannelUseCase`） |
| `core:designsystem` / `core:ui` | 主题设计系统、焦点控制、列表基础组件与 `Navigator` 抽象 |
| `player:api` / `player:media3` | 播放抽象与 `PlaybackManager` / ExoPlayer 实现（SurfaceView、按档位自适应缓冲） |
| `source:api` | 数据源抽象（`LiveSource` / `VodSource` / `BrowseSource` / `SearchableSource`）与通用解析器 |
| `source:cctv` `iptv` `tvbox` `smb` `local` | 当前已接入的数据源实现模块 |
| `feature:*` | 各页面功能：`home`、`live`、`vod`、`browse`、`search`、`history`、`settings`、`player` |

## 接入新数据源（3 步）

1. 新建 `source:<name>` 模块，根据能力实现 `LiveSource`、`VodSource`、`BrowseSource` 或 `SearchableSource`。
2. 声明 Hilt 绑定模块：
   ```kotlin
   @Binds @IntoSet abstract fun bindSource(impl: MySource): SourceProvider
   ```
3. 在 `app/build.gradle.kts` 中添加 `implementation(project(":source:<name>"))`。
   若需要自定义协议解析（如 `nfs://`），通过 `@Binds @IntoMap @StringKey("nfs")` 注入 `DataSource.Factory` 即可。

## 低配机型约束

- **零初始化开销**：`Application.onCreate` 严禁阻塞式 I/O，数据库、网络、爬虫与播放器一律按需懒加载。
- **单播放器铁律**：全局仅维持一个播放实例，离开播放页立即 `release()` 释放硬件解码器。
- **界面渲染防卡顿**：RecyclerView 配合 DiffUtil，低配档位关闭列表动画；Coil 图片限制采样尺寸；不使用 Compose，不使用高耗能毛玻璃图层。
- **低频进度通知**：进度更新仅在控制栏可见时 1 秒轮询，严禁将高频进度推入全局 `StateFlow`。

## 当前完成度与规划

| 状态 | 内容 |
|---|---|
| **已实现** | 多模块依赖与 DI 契约；IPTV/M3U/TXT 导入与 XMLTV 解析；央视官方高清点播与直播原生播放；TVBox CMS/Jar/JS/Python 分类、详情、搜索与解析；Samba 与本地媒体浏览；音轨与外挂字幕匹配；凭据加密安全存储；视口内容预取与连续切台优化 |
| **能力边界** | 点播仅使用原生播放器，不回退 WebView；央视默认高清，不支持 UDRM/Widevine/HEVC；脚本仅支持已实现的兼容沙箱契约；预置入口及其他第三方订阅的可用性取决于上游 |
| **进行中 / 待实现** | 一期进行中：TVBox 多层仓库选择与配置文件导入、设置页缓存清理入口、TV 高规格画质音效实测；二期规划：系统级画中画、NFS/Alist 等；详见 [路线图](docs/ROADMAP.md) |

## 相关文档

- [工程说明与代理约束](AGENTS.md)
- [点播与脚本兼容范围](docs/TVBOX_CCTV.md)
- [开发路线图](docs/ROADMAP.md)
