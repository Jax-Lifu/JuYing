# 聚映 (JuYing) — Android 端

面向 **电视 / 平板 / 手机** 的高性能播放器，minSdk 28 (Android 9)，协议 GPL-3.0。
第一期：**央视 (CCTV)、TVBox、IPTV、本机与移动存储、局域网 Samba**。

点播、详情、选集与逐源搜索已接入原生 View 页面。点播列表在剩余约一屏内容时提前加载下一页，封面也沿滚动方向提前准备一屏，后台追加不显示加载动画；首次加载保留反馈，失败时保留已有内容并提供重试。本次按用户指定的候选订阅，预置「金牌 · 肥猫」「急救 · 肥猫」两个经 Cayin 抽测的站点；来源管理支持编辑、停用、删除，删除后不会自动恢复。其余 TVBox 订阅由用户添加，央视保留官方入口。

IPTV 支持 M3U/TXT 地址或系统文件选择器导入，保存前可检查连接；XMLTV 节目单可读取列表声明或手动填写，支持 gzip。来源地址、账号、密码和附加参数加密保存，旧记录在读取时迁移。播放历史保留节目和分集信息，退到后台保存进度，返回后恢复原先的播放或暂停状态。

文件页使用应用内的存储位置列表、目录和路径导航，浏览及播放不跳转系统文件浏览器。本机、已挂载的移动存储与 SMB 共用浏览界面，匹配同目录字幕，播放返回后恢复目录。首次访问本机文件时申请文件访问权限；Android 11 及以上由用户在系统授权页允许访问，授权后返回聚映继续浏览。

点播分类随上滑吸顶，超出一行时可通过全部分类选择；详情、来源切换与主要操作使用图标加文字。播放器顶部显示片名与分集，底部提供进度、上一集/下一集、清晰度、倍速、音轨与字幕；清晰度来自当前流的实际视频轨道，支持自动选择。手机竖屏分行显示控制项，电视使用更大的按钮与遥控器焦点。

## 首次构建
1. 安装 JDK 17、Android SDK 36 和 Python 3.11，并将 Python 3.11 加入当前构建进程的 PATH。
2. 用 Android Studio 打开本目录，或运行仓库自带的 `gradlew.bat`；依赖版本统一在 `gradle/libs.versions.toml` 管理。
3. 运行 `gradlew.bat testDebugUnitTest :core:model:test :source:api:test`，再运行 `gradlew.bat :app:assembleDebug`。
4. Jar、QuickJS、CPython 与文件播放的设备回归位于 `app/src/androidTest`。先在文件页打开本机存储并允许文件访问，再设置 `ANDROID_SERIAL`，运行 `gradlew.bat :app:connectedDebugAndroidTest`。

Windows 若出现 JDK loopback/Unix socket 路径错误，将当前进程的 `TEMP`、`TMP` 设为已创建的短路径后重试。Python 3.11 用于同时保留 32 位和 64 位 ARM 支持；不要单独升级为仅支持 64 位的 Python 版本。

## 架构（参考 Now in Android，UI 用 View）
```
UI 层      Fragment / PlayerActivity ← ViewModel (StateFlow<UiState>)
Domain 层  UseCase（跨 Repository 才写）
Data 层    Repository（offline-first，只暴露 Flow） → SourceRegistry → source:*
```
- 单 Activity 为主：`MainActivity`(Fragment + Navigation) + 独立 `PlayerActivity`。
- 一套 View 代码适配三种设备：`layout/`(手机底栏) `layout-sw600dp/`(平板侧栏) `layout-television/`(电视侧栏)，数值走 `values-*`。
- feature 之间**禁止互相依赖**（`AndroidFeatureConventionPlugin` 在配置阶段强制检查，也禁止依赖 `source:*` / `player:media3`）；跨页面跳转统一走 `core:ui` 的 `Navigator`。

## 模块
| 模块 | 职责 |
|---|---|
| `app` | 入口、导航图、`Navigator` 实现、把所有模块在 Hilt 里组装 |
| `core:model` | 纯 Kotlin 领域模型 |
| `core:common` | 调度器注入、`DeviceProfile`（设备形态 + 性能档位 LOW/MID/HIGH） |
| `core:network` | OkHttp（缓存与并发按性能档位调整）、`fetchText` |
| `core:database` / `core:datastore` | Room(源/历史/收藏) / DataStore(设置) |
| `core:data` | Repository + `SourceRegistry`（Hilt 多重绑定收集数据源） |
| `core:domain` | `GetPlayItemUseCase`、`ZapChannelUseCase` |
| `core:designsystem` / `core:ui` | 主题与资源 / 基类、焦点、图片、Navigator |
| `player:api` / `player:media3` | 内核抽象 + `PlaybackManager` / ExoPlayer 实现（SurfaceView、按档位调缓冲、协议路由） |
| `source:api` | `LiveSource` / `VodSource` / `BrowseSource` / `SearchableSource` / `SourceDiscoveryProvider` + m3u/txt 解析器（含 `#EXTVLCOPT` 请求头）+ 外挂字幕自动匹配 |
| `source:cctv` `iptv` `tvbox` `smb` | 各数据源（已预留 `CLOUD_DRIVE` / `ALIST` / `WEBDAV` / `NFS` / `LOCAL` / `USB_STORAGE` / `UPNP` 统一能力与动态发现契约，见 [`AGENTS.md`](AGENTS.md)） |
| `feature:*` | home / live / vod / browse / search / history / settings / player |

## 新增一个数据源（3 步）
1. 新建 `source:xxx`，实现 `LiveSource` / `VodSource` / `BrowseSource` 中需要的接口。
2. 写一个 Hilt Module：`@Binds @IntoSet abstract fun source(impl: Xxx): SourceProvider`。
3. 在 `app/build.gradle.kts` 加 `implementation(project(":source:xxx"))`。
需要自定义播放协议（如 `nfs://`）时，再加 `@Binds @IntoMap @StringKey("nfs")` 绑定一个 `DataSource.Factory`（参考 `SmbDataSourceModule`）。

## 低配机（1–4GB / Android 9）约定
- `Application.onCreate` 只做极轻量初始化；数据库、OkHttp、爬虫、播放器全部懒加载。
- `DeviceProfile.tier` 驱动：HTTP 缓存/并发、播放缓冲时长与字节上限、列表动画开关。
- 列表一律 RecyclerView + DiffUtil，关闭 itemAnimator；图片 Coil 限制解码尺寸。
- Fragment 用 `ViewBindingFragment`（销毁时释放 binding）+ `repeatOnLifecycle(STARTED)`（后台不刷新 UI）。
- 全局最多一个播放器；离开播放页立即 `release()`；视频输出用 SurfaceView（HDR/杜比视界/4K）。
- 进度不进 StateFlow，控制条可见时 1s 轮询。
- release 开启 R8 + 资源压缩，仅打 `arm64-v8a`、`armeabi-v7a`。

## 当前完成度
| 状态 | 内容 |
|---|---|
| 已实现 | 工程与依赖边界、DI、数据库、m3u/txt、IPTV、SMB 与 Media3 基础链路；TVBox CMS XML/JSON、Jar/JS/Python 的分类、列表、详情、搜索和播放解析；央视专辑与分页分集；首页、局域网浏览、历史、音轨/字幕选择；来源添加、检查、编辑、启停、删除；IPTV 文件导入与 XMLTV；凭据加密及有界目录/频道缓存 |
| 能力边界 | 点播仅使用原生播放器；央视 H5E/H.264 默认高清，标清须手动选择。解析失败明确提示，不切到网页；央视搜索按栏目目录分页匹配。脚本只支持已实现的调用契约，详见 [点播与脚本兼容范围](docs/TVBOX_CCTV.md) |
| 仍待实现 | TVBox 多层仓库选择、完整 drpy 宿主扩展与通用嗅探/代理、TVBox 本地配置文件导入、缓存清理入口、画中画；未接入的数据源协议不能视作已有功能 |
| 第二期 | 见 `docs/ROADMAP.md` |

## 调研参考

- [zhuiju.me 对聚映的参考价值](docs/research/2026-10-27-zhuiju-assessment.md)：开源项目筛选、现有能力对照与后续研究顺序。
