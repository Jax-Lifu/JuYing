# Aerial TV 对聚映的性能与包体借鉴

日期：2026-10-27。本文保留当时的只读源码与官方发布元数据研究快照；该研究阶段未安装 Aerial、未测试设备性能、未修改聚映源码。

后续落地：频道选中态 payload 与连续切台修复已完成，见[切台优化与验证记录](2026-10-27-channel-switch-optimization.md)。下文体积与性能数据仍属于各自标注的旧产物。

## 核对版本与包体

上游源码固定在 [`2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34`](https://github.com/pengchujin/aerial-tv/commit/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34)，完整版版本名 1.61，Lite 版本名 1.2。[构建配置](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/build.gradle.kts#L10-L20)、[Lite 配置](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/lite/build.gradle.kts#L12-L23)。

查询期间上游发布了 v1.61，以下是 GitHub Release API 的资产大小，并非构建预测或下载后的磁盘占用：

| v1.61 发布资产 | 字节 | MiB |
| --- | ---: | ---: |
| aerial-standard.apk | 2,992,673 | 2.854 |
| aerial-guard.apk | 2,991,988 | 2.853 |
| aerial-lite.apk | 929,047 | 0.886 |

来源：[v1.61 发布页](https://github.com/pengchujin/aerial-tv/releases/tag/v1.61)、[发布元数据 API](https://api.github.com/repos/pengchujin/aerial-tv/releases/latest)。发布时刻为 2026-10-27 17:32:46（UTC+8）。`latest` 会随以后发布改变，本文保留当次 tag 和数值。

## 为什么包小

1. **产品范围不同。** Aerial 是桌面：主要是 App 磁贴、系统入口、壁纸和屏保。它不是聚映这样的多源聚合播放器。不能把两者体积差全归因于 UI 框架或代码质量。[README](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/README.md)
2. **完整版确实用了 Compose。** 显式 UI 依赖是 Compose UI/Foundation/Animation、Activity/Lifecycle；没有 Material、androidx.tv，也没有完整图标依赖。播放器依赖限于 Media3 ExoPlayer/DataSource/Database，此外是轻量局域网 HTTP 服务和二维码库。源码依赖列表支持“有选择地引依赖”，不支持“只有原生 View 才能小”的结论。[app/build.gradle.kts:88-109](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/build.gradle.kts#L88-L109)
3. **Release 同时裁剪代码和资源。** `isMinifyEnabled`、`isShrinkResources` 均开启，并使用 optimize ProGuard 配置；Lite 也相同。没有证据表明模块数量本身决定 APK 大小。[完整版配置:56-62](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/build.gradle.kts#L56-L62)、[Lite 配置:40-46](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/lite/build.gradle.kts#L40-L46)
4. **视觉内容不等于内置大素材。** 航拍目录主要保存 URL 和说明，影片走网络；内置壁纸由 Gradients 绘制，图标用路径数据。漂亮的大画面不必作为整段视频或大量大图打进 APK。[架构目录与屏保说明](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/docs/ARCHITECTURE.md#L35-L42)、[屏保说明](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/docs/ARCHITECTURE.md#L154-L159)
5. **Lite 是另一个更小的实现。** 它不用 Compose/AndroidX，直接使用平台 View，显式运行依赖仅 NanoHTTPD 与 ZXing。Lite 的数字不能用来代表完整版的功能和依赖成本。[lite/build.gradle.kts](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/lite/build.gradle.kts#L4-L6)、[依赖:119-125](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/lite/build.gradle.kts#L119-L125)

## 为什么看起来流畅：源码可确认的具体手段

### 减少每帧重画，而不是只缩短动画

玻璃材质使用预先模糊的小壁纸，`drawWithCache` 生成遮罩与 shader；缓存 GraphicsLayer，仅在位置、根尺寸或换图淡入状态改变时重新 record，正常焦点移动只合成已有图层。流畅模式直接绘制不透明平均色，避免完整玻璃图层的成本。[LiquidGlass.kt:62-130](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/ui/components/LiquidGlass.kt#L62-L130)

上游明确要求首页每帧最多一次全屏绘制、静止时无持续动画，并要求新全屏效果先测帧耗时。文档报告某设备从约 65ms 降到 18ms，以及某面板从约 53ms 降到 25ms；这些是**作者的特定设备历史报告**，不是本轮复测，也不能证明所有电视始终 60fps。[性能约束:95-110](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/docs/ARCHITECTURE.md#L95-L110)

对聚映最有价值的是减少透明层、全屏重画及焦点变化时的额外工作；无需引入 Compose 或玻璃效果。

### 重计算移出主线程，优先满足首屏

`HomeViewModel.reload` 并行读取 App 列表和输入源；冷启动完整读取前 13 个磁贴，其他缓存先读名称/颜色占位，再后台补齐。App 查询及磁贴构建在 `Dispatchers.Default`；图片已有磁盘缓存，键包含应用更新时间、像素尺寸、风格、语言、Aerial 版本，避免每次启动重新加工。[HomeViewModel.kt:202-244](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/HomeViewModel.kt#L202-L244)、[首批数量:71](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/HomeViewModel.kt#L71)、[Apps.kt:195-203](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/apps/Apps.kt#L195-L203)、[TileDiskCache.kt:24-47](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/apps/TileDiskCache.kt#L24-L47)

圆角和描边预制图每批 5 张在后台生成，完成一批再刷新绘制；内存压力时释放非静止尺寸的焦点磁贴与缩略图。[AppTile.kt:575-626](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/ui/home/AppTile.kt#L575-L626)、[MainActivity.kt:314-322](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/MainActivity.kt#L314-L322)

### 低端机主动减少装饰成本

自动低端判断使用系统 low-RAM 标记、物理内存低于 1800MiB、Android 7 以下、CPU 核数不超过 2，而不是只靠品牌名单。流畅模式减掉高光、视差、阴影等装饰，保留交互。[DeviceClass.kt:7-25](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/system/DeviceClass.kt#L7-L25)、[AppTile.kt:430-470](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/ui/home/AppTile.kt#L430-L470)

播放流的缓冲目标按画质设为 24/32/48MiB，并优先遵守大小阈值；屏保预取只保留开场与索引，磁盘缓存上限 48MiB。这里是缓冲和缓存预算，**不是整个进程内存上限**。[AerialStream.kt:51-105](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/wallpaper/AerialStream.kt#L51-L105)

### Release、AOT 与测量条件也影响观感

上游安装脚本实际先启动一次，等待 5 秒，再执行 `cmd package compile -m speed -f`。源码还包含 Baseline Profile。比较聚映 Debug 与 Aerial 经脚本安装的 Release，会混入构建和编译状态差异。[install.sh:316-326](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/tools/install.sh#L316-L326)、[baseline-prof.txt](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/baseline-prof.txt)

`FrameStats` 用独立线程接收 FrameMetrics，保留最近 600 帧，输出 median/p90/p99/最慢帧；但跳过启动后 5 秒和首帧，因此**不能作为冷启动指标**。固定 16.7ms 的超时统计在 120Hz 上也不是相应的单帧预算。值得借鉴的是把设备、构建、操作场景、帧分位和编译状态一起记录。[FrameStats.kt:11-58](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/system/FrameStats.kt#L11-L58)

## 不应直接照搬

- 保持聚映现有 Fragment/ViewBinding/RecyclerView 与 SurfaceView。Aerial 的框架选择与其产品边界不同，没有源码证据支持为模仿它而重写聚映 UI。
- Aerial 的 `Wallpapers` 在主线程读取并解码上次壁纸；这与聚映启动零阻塞约束冲突，不能把它的整套启动路径直接复制过来。[Wallpapers.kt:348-362](https://github.com/pengchujin/aerial-tv/blob/2b2eb21aa789b2f6526a7d9b7b2b92f175bd3a34/app/src/main/java/app/orchard/tv/wallpaper/Wallpapers.kt#L348-L362)
- 它的 Baseline Profile 粗粒度覆盖应用、Compose 和大量运行库。聚映如要增加，应按启动、导航、直播列表、播放进入等真实路径采集并验证，不能把通配规则当成已测收益。
- 桌面守护、通知监听复活和 HOME 接管是 Launcher 功能，聚映不需要为性能复制这些常驻机制。
- 上游部分文档仍有旧数据（例如 Lite 文档的约 700KB，与当前 release 929,047 bytes 不一致）。包体以固定 release 的官方资产元数据为准；性能以具体设备、版本、场景的测量为准。

## 聚映对照与建议顺序

本节依据本轮对当前工作区源码和已有 APK 的并行只读核查；未修改业务源码。

聚映已经具备多项同方向设计：`JuyingApplication` 使用 Lazy，LOW 档 Coil 内存缓存 8%、RGB565、关闭 crossfade；`ImageExt` 默认按 256px 加载封面；点播列表已有 DiffUtil、回收池和预绑定，关闭 itemAnimator；播放页仅在前台且控制栏可见时每秒更新一次进度；播放器使用 SurfaceView，LOW 档目标缓冲为 24MiB。这些应保留，不需重复发明。[Application](../../app/src/main/kotlin/com/flytech/juying/JuyingApplication.kt)、[图片加载](../../core/ui/src/main/kotlin/com/flytech/juying/core/ui/ImageExt.kt)、[点播列表](../../feature/vod/src/main/kotlin/com/flytech/juying/feature/vod/VodFragment.kt)、[播放页](../../feature/player/src/main/kotlin/com/flytech/juying/feature/player/PlayerActivity.kt)、[播放内核](../../player/media3/src/main/kotlin/com/flytech/juying/player/media3/Media3Engine.kt)。

已有 Debug APK 体积核查结果：2026-10-27 15:09:46（UTC+8）产物为 79,147,258 bytes（75.481MiB）。按 ZIP 条目的压缩长度，DEX 合计约 32.831MiB；Python/Chaquopy 与相关 OpenSSL/SQLite 原生库合计 36,080,996 bytes（34.410MiB，约占包 45.59%）；UI 资源约 1.836MiB；QuickJS 两个 ABI 合计约 1.261MiB。这个已有包**尚未证明与本轮查看的源码完全一致**，数值只说明该产物的主要重量所在。

该包的 ABI 专属条目合计约为 arm64 17.608MiB、armv7 11.934MiB，含 Chaquopy 的 ABI assets。分发 arm64 独立 APK 理论上可以排除约 11.93MiB 的另一 ABI 条目负载，实际成品大小仍须构建验证。另有 10 月 24 日的旧 Release 约 6.234MiB，但没有当前 Python/QuickJS 运行时，不能把这两个包的差额解释成 R8 效果，更不能用旧 Release 代表当前功能的发布体积。

建议按下列顺序推进：

1. **先建立相同条件的 Release 基线。** 当前源码同一提交、同设备、同 ABI，记录首屏时间、遥控器连续导航 P95/P99、峰值/PSS、后台空闲帧、进入播放首帧。保留常规安装与 AOT 状态，不能拿 Debug 对经脚本编译的 Aerial Release。冷启动与稳定导航分开统计。
2. **消除焦点切换的冗余工作（已落地）。** 研究时直播 `ChannelAdapter.select` 对旧/新条目完整重绑并再次请求 logo；后续已改为选中态 payload，仅更新 `isSelected`。真机测试验证不重绑图片和文案；尚未测量帧耗时收益。[落地记录](2026-10-27-channel-switch-optimization.md)、[Adapters.kt](../../feature/live/src/main/kotlin/com/flytech/juying/feature/live/Adapters.kt)
3. **按依赖和 ABI 管包体。** 保留现有 R8/资源裁剪，验证当前功能的 Release；若确有分发需求，再提供各 ABI 包。Python/Spider 是功能成本，不能为数字好看直接删掉；可在用户明确选择功能取舍后考虑轻量版本，默认不拆新产品、不破坏源兼容性。
4. **保持首屏与后台任务的优先级。** 复用现有图片加载器和列表机制，先测各首页任务的耗时、并发和取消；`observeSources` 冷流被多个消费者订阅、存储发现每次注册/枚举，值得测量重复工作，再决定是否在 Repository 层共享。不要先加一套全局缓存。
5. **把低端降级和性能证据做成闭环。** 复用 DeviceProfile，检查所有阴影、透明叠层、图片规格和动画是否真正服从档位；用有限的 FrameMetrics 采样或已有设备脚本记录结果。已有 build12 验证文档的 P95 85ms、最长 117ms 属于旧产物和特定场景，不能当成本轮或最终 build13 的复测通过。[已有验证记录](../UX_12_VERIFICATION_20261027.md)

## 验证边界

已完成：固定提交的构建与关键源码检查、官方 release 体积核对。

该只读研究未完成：下载解包 Aerial APK、Aerial 源码重建、目标 Android 设备上的安装/帧率/PSS/冷启动对照。聚映后续代码优化及验证单独记录于上方链接。本文描述可解释性能的设计手段，不保证复用某一手段就有相同收益。
