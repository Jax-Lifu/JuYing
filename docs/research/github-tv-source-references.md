# GitHub 播放源与 TV 功能参考

调研日期：2026-10-26（Asia/Shanghai）。范围：聚映 Android 原生版本的播放源扩展、遥控操作和电视端集成。本轮只记录参考，不引入依赖、不移植功能、不收集第三方媒体订阅。

## 优先看哪些

建议先看 **FongMi/TV、Kodi IPTV Simple、Jellyfin Android TV**：分别对应多源适配、直播节目单/回看、电视端导航与系统集成。局域网浏览补看 **VLC Android**；播放内核能力先查 **AndroidX Media3**；**SmartTube** 的帧率匹配和 **Tvheadend** 的家庭电视后端放在后续阶段。

这里的优先级是结合聚映现有接口和低配设备约束做出的建议，不是按 Star 数排名，也不代表已在 MX5 上验证。

## 仓库快照

以下仓库均通过 GitHub API 确认在调研时**未归档**；表中日期是所列默认分支 HEAD 的提交日期（UTC），不是 APK 发布日期。未归档不等于持续维护承诺。源码链接固定到本次读取的提交，便于后续复核。

| 项目 | 本次分支 / 提交 | HEAD 日期 | 根许可证与注意点 |
| --- | --- | --- | --- |
| [FongMi/TV](https://github.com/FongMi/TV) | `fongmi` / [aa30eb047c74](https://github.com/FongMi/TV/commit/aa30eb047c749fe5a96dd47b94947cda2421354f) | 2026-10-25 | [GPLv3](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/LICENSE.md)；第三方运行时另核对 |
| [jellyfin/jellyfin-androidtv](https://github.com/jellyfin/jellyfin-androidtv) | `master` / [fe4f0c278df2](https://github.com/jellyfin/jellyfin-androidtv/commit/fe4f0c278df26cdf1e71818e239a18190dac8f64) | 2026-10-25 | [GPLv2](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/LICENSE)；README 明示 master 不稳定 |
| [kodi-pvr/pvr.iptvsimple](https://github.com/kodi-pvr/pvr.iptvsimple) | `Piers` / [2066e6e6d9fc](https://github.com/kodi-pvr/pvr.iptvsimple/commit/2066e6e6d9fc34f7fe454d91025bcb56de156b74) | 2026-10-18 | [GPLv2](https://github.com/kodi-pvr/pvr.iptvsimple/blob/2066e6e6d9fc34f7fe454d91025bcb56de156b74/LICENSE.md)；本次读取的 CatchupController 标注 GPL-2.0-or-later |
| [videolan/vlc-android](https://github.com/videolan/vlc-android) | `master` / [2527071008b7](https://github.com/videolan/vlc-android/commit/2527071008b703d903866372719dd7b6c78b2a66) | 2026-10-21 | [README](https://github.com/videolan/vlc-android/blob/2527071008b703d903866372719dd7b6c78b2a66/README.md#license) 分别说明应用 GPLv2-or-later、LibVLC LGPLv2；不要混为一项许可 |
| [androidx/media](https://github.com/androidx/media) | `release` / [8c6678b657ed](https://github.com/androidx/media/commit/8c6678b657ede1e7883fc164ef73ed483c7796c3) | 2026-09-08 | [Apache-2.0](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/LICENSE) |
| [yuliskov/SmartTube](https://github.com/yuliskov/SmartTube) | `master` / [3d6aa1614241](https://github.com/yuliskov/SmartTube/commit/3d6aa1614241187f7c388d5f374e6f83b8579494) | 2026-10-25 | 当前根 [LICENSE 为 MIT](https://github.com/yuliskov/SmartTube/blob/3d6aa1614241187f7c388d5f374e6f83b8579494/LICENSE)；仓库包含独立第三方许可，README 还残留 GPL 引文，不能据根许可推定全部文件一致 |
| [tvheadend/tvheadend](https://github.com/tvheadend/tvheadend) | `master` / [51ec612fa22c](https://github.com/tvheadend/tvheadend/commit/51ec612fa22c4c78b4697e4c262c943da9cbd6cc) | 2026-10-22 | [GPLv3](https://github.com/tvheadend/tvheadend/blob/51ec612fa22c4c78b4697e4c262c943da9cbd6cc/LICENSE.md)；Linux 服务端 |

归档状态核对入口：[FongMi](https://api.github.com/repos/FongMi/TV)、[Jellyfin](https://api.github.com/repos/jellyfin/jellyfin-androidtv)、[Kodi IPTV Simple](https://api.github.com/repos/kodi-pvr/pvr.iptvsimple)、[VLC](https://api.github.com/repos/videolan/vlc-android)、[Media3](https://api.github.com/repos/androidx/media)、[SmartTube](https://api.github.com/repos/yuliskov/SmartTube)、[Tvheadend](https://api.github.com/repos/tvheadend/tvheadend)。这些 API 返回的是实时状态，未来可能变化；上表是本次快照。

## 1. FongMi/TV：最接近聚映的多源与直播参考

**已确认的实现**：`Spider` 契约覆盖首页、分类、详情、分页搜索、播放解析和直播；`BaseLoader` 分流 Java/Jar、QuickJS、Python、Node 运行时。`LiveParser` 处理 M3U/TXT、频道分组、`tvg-id`、节目单地址、请求头及 catch-up 属性。`LivePlaybackController` 把频道、线路和待完成请求分开管理，并在应用异步结果前检查它仍是当前请求。[Spider](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/crawler/Spider.java)、[BaseLoader](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/api/loader/BaseLoader.java)、[LiveParser](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/api/parser/LiveParser.java)、[LivePlaybackController](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/playback/live/LivePlaybackController.java#L287-L290)

**聚映可以借鉴**：以 `VodSource` / `LiveSource` 为稳定入口，把子站、分页、解析结果和线路头信息转换成现有 `SubSource`、`PlayRequest`、`PlayItem`，避免 UI 直接认识 Spider 类型；后续直播体验按“频道选择 → 地址解析 → 播放 → 失败切线”梳理状态。FongMi 已有独立 leanback/mobile 目录，也适合作为电视和触屏行为分离的参考。[TV 直播页](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/leanback/java/com/fongmi/android/tv/ui/activity/LiveActivity.java)、[手机直播页](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/mobile/java/com/fongmi/android/tv/ui/activity/LiveActivity.java)

**暂不照搬**：多运行时和多内核全量集成。聚映应先把既定 CMS/type 0/1 链路做完整，再分别评估 Jar/JS/Python 的可信来源、生命周期、取消、内存和超时边界；“能动态加载”不等于“已安全隔离”。上游爬虫开发资料入口是 README 指向的 [FongMi/CatVodSpider](https://github.com/FongMi/CatVodSpider)，不应以不明来源的接口合集替代契约与测试。

## 2. Kodi IPTV Simple：EPG 和回看语义优先参考

**已确认的实现**：支持 M3U 与 XMLTV、多组配置、XMLTV gzip/xz、频道/节目映射和 catch-up；回看要求上游提供相应能力，时移还取决于实际 inputstream。`CatchupController` 区分直播、从节目单回看、时间窗口和节目起止缓冲。[README](https://github.com/kodi-pvr/pvr.iptvsimple/blob/2066e6e6d9fc34f7fe454d91025bcb56de156b74/README.md)、[CatchupController](https://github.com/kodi-pvr/pvr.iptvsimple/blob/2066e6e6d9fc34f7fe454d91025bcb56de156b74/src/iptvsimple/CatchupController.cpp)

**聚映可以借鉴**：先实现 `LiveSource.epg()`，统一 `tvg-id`、XMLTV channel id、时区和跨日节目；回看能力之后单独建模，不把所有直播都显示成可拖动进度。针对同名不同频道、夏令时/时区偏移、压缩 XMLTV、过期回看窗口建立固定测试样本。低配盒子上采用流式解析、有界时间窗和缓存，避免每次换台全量解析节目单。

**暂不照搬**：Kodi 的 C++ PVR 插件接口、完整设置矩阵及 ffmpegdirect 时移实现。它们依赖 Kodi 宿主；适合借鉴格式和行为，不是可直接添加到 Android Gradle 的播放源库。

## 3. Jellyfin Android TV：遥控焦点、直播切换和系统入口

**已确认的实现**：`FocusPersistManager` 按稳定 key 保存/恢复焦点；`PreviousLiveTvChannelAction` 提供返回上一直播频道行为；`LeanbackChannelWorker` 发布 Android TV 首页频道与 Watch Next，并先检测设备是否提供 TV content provider。仓库还将 Media3 会话集成单独组织为模块。[焦点恢复](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/app/src/main/java/org/jellyfin/androidtv/ui/navigation/focus/FocusPersistManager.kt)、[上一频道](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/app/src/main/java/org/jellyfin/androidtv/ui/playback/overlay/action/PreviousLiveTvChannelAction.kt)、[TV 首页集成](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/app/src/main/java/org/jellyfin/androidtv/integration/LeanbackChannelWorker.kt)、[MediaSession](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/playback/media3/session/src/main/kotlin/MediaSessionService.kt)

**聚映可以借鉴**：在 `feature:live` / `feature:browse` 用稳定条目 id 保存返回位置和焦点；列表刷新后恢复到仍存在的条目；弹窗关闭返回原控制项；换台保留上一频道。系统首页推荐与继续观看以后再接入 `app`，能力缺失的机顶盒应自然跳过。

**适配边界**：上面的新焦点管理器使用 Compose，聚映明确使用 View/RecyclerView，因此只借鉴 key 与恢复时机，不能直接复制组件。Jellyfin 是其服务端的客户端，不是通用站点解析器；接入 Jellyfin 内容需要独立需求与鉴权适配。README 明确要求生产部署/长期 fork 使用对应 release 分支，不能将此次 master 快照当成稳定交付基线。[README](https://github.com/jellyfin/jellyfin-androidtv/blob/fe4f0c278df26cdf1e71818e239a18190dac8f64/README.md#branching)

## 4. VLC Android：局域网目录浏览与 TV 文件选择

**已确认的实现**：`NetworkProvider` 在 IO 调度器执行浏览，通过 LibVLC `MediaBrowser` 发现网络共享，并区分网络收藏与发现结果；电视端有独立 `FileBrowserTvFragment`。README 列出 SMB、FTP、SFTP、NFS、UPnP/DLNA 等 LibVLC 网络浏览能力。[NetworkProvider](https://github.com/videolan/vlc-android/blob/2527071008b703d903866372719dd7b6c78b2a66/application/vlc-android/src/org/videolan/vlc/providers/NetworkProvider.kt)、[TV 文件浏览](https://github.com/videolan/vlc-android/blob/2527071008b703d903866372719dd7b6c78b2a66/application/television/src/main/java/org/videolan/television/ui/browser/FileBrowserTvFragment.kt)、[README](https://github.com/videolan/vlc-android/blob/2527071008b703d903866372719dd7b6c78b2a66/README.md#libvlc)

**聚映可以借鉴**：`SourceDiscoveryProvider` 输出动态发现结果，`BrowseSource` 负责目录读取，手动配置与自动发现保持同一列表体验；TV 文件夹返回、网络不可用、收藏入口和凭据交互分开处理。后续实现 UPnP/本地/USB 时可复用现有 `FileEntry` 和外挂字幕匹配链路。

**暂不照搬**：为获取发现能力直接替换 Media3 为 LibVLC，或把媒体库常驻扫描搬到 `Application.onCreate`。这会改变 APK 体积、内存、解码与发布链路，需另行评估。VideoLAN 的问题与合并请求入口在其 [GitLab](https://code.videolan.org/videolan/vlc-android/)，GitHub 阅读入口不能代替上游协作流程。[贡献说明](https://github.com/videolan/vlc-android/blob/2527071008b703d903866372719dd7b6c78b2a66/README.md#pull-requests)

## 5. AndroidX Media3：先用现有内核提供的能力

**已确认的实现**：View 体系有 `TrackSelectionDialogBuilder`，可按音频/字幕轨道构建选择界面；`VideoFrameReleaseHelper` 管理帧释放时间与 Surface 帧率提示；`DefaultDataSource` 已内置 UDP。RTSP 则需要独立 `media3-exoplayer-rtsp` 模块，官方声明的 RTP-over-UDP 是单播，不应推导成任意裸 RTP/组播均支持。[轨道选择](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/ui/src/main/java/androidx/media3/ui/TrackSelectionDialogBuilder.java)、[帧率处理](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/video/VideoFrameReleaseHelper.java)、[DataSource](https://github.com/androidx/media/blob/8c6678b657ede1e7883fc164ef73ed483c7796c3/libraries/datasource/src/main/java/androidx/media3/datasource/DefaultDataSource.java)、[RTSP 官方文档](https://developer.android.com/media/media3/exoplayer/rtsp)

**聚映可以借鉴**：音轨/字幕选择先扩展 `player:api` 的必要能力，实现在 `player:media3`，保持 feature 不依赖 Media3；后台播放若获授权再参考 [官方 session 示例](https://github.com/androidx/media/tree/8c6678b657ede1e7883fc164ef73ed483c7796c3/demos/session)。新增协议先确认现有内核和依赖，再决定是否写自定义 DataSource。

**验证边界**：Surface 帧率提示不是“每台电视都会自动切到正确 HDMI 模式”的保证。轨道、字幕、RTSP、HDR 和音频直通都必须用目标设备与明确的样本流验收；不因上游宣称支持而替聚映声明已支持。

## 6. SmartTube：帧率匹配的设备差异与恢复流程

**已确认的实现**：`AutoFrameRateController` 保存原始显示状态，播放后延迟应用 AFR，处理切换时暂停/恢复，以及关闭 AFR 后恢复原状态；README 说明 AFR 并非所有硬件都工作良好，也明确不面向手机触控使用。[AFR 控制器](https://github.com/yuliskov/SmartTube/blob/3d6aa1614241187f7c388d5f374e6f83b8579494/common/src/main/java/com/liskovsoft/smartyoutubetv2/common/app/models/playback/controllers/AutoFrameRateController.java)、[README](https://github.com/yuliskov/SmartTube/blob/3d6aa1614241187f7c388d5f374e6f83b8579494/README.md)

**聚映可以借鉴**：将“请求模式 → 等待显示切换 → 恢复原播放意图 → 退出恢复”作为后续 AFR 测试清单。遥控功能可以参考其交互，但不能把 TV-only 的输入假设带入聚映手机和平板布局。

**暂不照搬**：旧 ExoPlayer 分支、机型绕过和外部 AFR 辅助应用集成。先测 Media3/系统 API 的现有效果，再针对确有证据的 MX5 问题增加最小兼容处理；也不把某一网站的提取逻辑作为通用播放源机制。

## 7. Tvheadend：家庭直播后端，按需接入

**已确认的能力**：Linux 服务端支持 DVB/ATSC、HDHomeRun、IPTV、SAT>IP 等输入，提供 HTTP/HTSP 等输出及 DVR。官方 HTTP 文档提供频道/录像播放列表、XMLTV 和短时播放 ticket；JSON API 可按频道、时间等查询 EPG。[README](https://github.com/tvheadend/tvheadend/blob/51ec612fa22c4c78b4697e4c262c943da9cbd6cc/README.md)、[播放列表与 XMLTV](https://docs.tvheadend.org/documentation/development/json-api/other-functions)、[EPG API](https://docs.tvheadend.org/documentation/development/json-api/api-description/epg)

**聚映可以借鉴**：若用户已有 NAS/电视后端，先用其 M3U + XMLTV 复用 IPTV 链路；确有录像、账户或按需 ticket 需求后，再设计独立服务端适配。票据在播放时解析，不能把过期地址长期当成频道主键。

**暂不照搬**：把 DVR 调度、录制、转码服务器搬进低内存 Android 盒子，也不为“将来可能需要”预先实现 HTSP。此项目是源的后端选择，不是聚映前端的替代品。

## 映射到聚映的后续顺序

以下仅是候选顺序；本轮仍只修复已确认问题。已有模块依据 [源契约](../../source/api/src/main/kotlin/com/flytech/juying/source/api/Sources.kt)、[播放模型](../../core/model/src/main/kotlin/com/flytech/juying/core/model/Play.kt) 与 [路线图](../ROADMAP.md)。

| 顺序 | 候选工作 | 参考 | 聚映落点 | 开始前应明确的验收 |
| --- | --- | --- | --- | --- |
| 1 | 用户配置 IPTV + EPG 的完整闭环 | Kodi、FongMi | `source:iptv`、`LiveSource.epg`、`feature:live` | 导入/刷新/删除；频道 id 映射；跨日/时区；失败保留可用缓存；大节目单内存有界 |
| 2 | TV 基本操作和音轨/字幕选择 | Jellyfin、Media3 | `core:ui`、`feature:player`、`player:api/media3` | 全程 D-Pad 可达；返回恢复焦点；连续换台最后一次生效；弹窗关闭返回原控制项 |
| 3 | TVBox 已规划的 CMS/type 0/1 完整链路 | FongMi | `source:tvbox`、`VodSource`、`SubSource` | 分类→搜索→详情→选集→解析→播放；子站隔离；请求头与取消；不支持类型明确显示 |
| 4 | 局域网/本机发现与目录体验 | VLC | `BrowseSource`、`SourceDiscoveryProvider`、`feature:browse` | 断网/移除设备可取消；重新发现不重复；凭据隔离；特殊路径与同目录字幕 |
| 5 | 首页推荐、继续观看、AFR | Jellyfin、Media3、SmartTube | `app`、`player:media3` | 缺系统 provider 时可跳过；低频更新；MX5 显示切换/退出恢复与音画实测 |
| 按需 | 家庭电视后端与录像 | Tvheadend | 先复用 IPTV，必要时另立 source 适配 | 真实后端鉴权、ticket 到期、EPG、录像权限与 seek |

所有候选仍受聚映约束：View/RecyclerView、单播放器、LOW 档 24MB 播放缓冲上限、懒初始化、用户自行配置第三方源。参考项目的功能数量不能成为放宽这些限制的理由。[工程约束](../../AGENTS.md)

## 复用与证据边界

- 本文确认到仓库、所列文档/源码和接口层面；没有安装这些项目的 APK，没有对其做安全审计或 MX5 性能对比。
- 借鉴设计、复制源码、集成库和执行外部插件是不同决策。真正复用时再核对目标文件及依赖的许可证、版权和发布要求；本表不作整仓兼容性结论。
- 动态脚本/Jar、登录凭据、网络遥控和临时播放地址均需要独立的信任与生命周期设计；本轮不引入这些能力。
- 不记录媒体盗版订阅、账户 Cookie、临时 token 或可用源承诺。上游有某功能，不表示其媒体站点、协议和设备兼容性已在聚映验证。
