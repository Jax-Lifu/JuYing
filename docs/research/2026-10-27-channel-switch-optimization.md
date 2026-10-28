# 连续切台优化与验证

日期：2026-10-27。范围：现有 Android 原生 View / Media3 工程的直播切台状态与列表更新；不新增依赖、播放源或播放器实例。

## 问题与修复

- A 正在播放、B 正在解析时再次按下一台，原实现仍从 A 计算，重复请求 B。现在优先以待切频道为基点；列表查询未返回时累计正反方向输入，新输入立即取消旧解析，最终只应用有效目标。
- 重新选择正在播放的 A，原实现直接返回，未取消待切 B。现在取消待切请求并保留 A，不重复 prepare。
- 查询期间允许继续使用直播上一台/下一台按钮，也可返回取消；点播选集仍保持原有等待限制。列表查询失败保留当前播放、显示可重试状态；取消清空待处理偏移。
- 首台尚未解析时也接受频道键；列表为空或原频道消失时恢复原请求，避免取消后永久加载。迟到的成功、失败结果均受协程有效性检查约束。
- 频道列表选中态使用 RecyclerView payload，仅刷新旧/新两项的 `isSelected`；不重新请求台标或重绑文案。空 payload 或未知 payload 仍走完整绑定。

修改入口：[PlayerViewModel](../../feature/player/src/main/kotlin/com/flytech/juying/feature/player/PlayerViewModel.kt)、[PlayerActivity](../../feature/player/src/main/kotlin/com/flytech/juying/feature/player/PlayerActivity.kt)、[ChannelAdapter](../../feature/live/src/main/kotlin/com/flytech/juying/feature/live/Adapters.kt)。

## 参考依据及取舍

[zhuiju.me](https://zhuiju.me/) 是导航页；本轮参考其链接到的 FongMi 源码，而非假定导航站自身具有播放器实现。固定提交 `123cc086159b0f13bf54bdf64bacbc259ca47c88` 的 [ViewModelTaskRunner](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/model/ViewModelTaskRunner.java#L27-L48) 同时取消旧任务并校验结果身份；[LivePlaybackController](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/playback/live/LivePlaybackController.java#L287-L290) 校验待播放请求。聚映沿现有协程和单播放器边界补齐缺口，没有复制整套控制器。完整研究见 [zhuiju 参考评估](2026-10-27-zhuiju-assessment.md)。

Aerial 本轮复核到 `b8e84e90419c0e96069d557b740503e56fdc2cfb`。它是 TV Launcher；[焦点恢复](https://github.com/pengchujin/aerial-tv/blob/b8e84e90419c0e96069d557b740503e56fdc2cfb/app/src/main/java/app/orchard/tv/ui/home/HomeScreen.kt#L334-L370) 与[低成本绘制](https://github.com/pengchujin/aerial-tv/blob/b8e84e90419c0e96069d557b740503e56fdc2cfb/app/src/main/java/app/orchard/tv/ui/components/LiquidGlass.kt#L91-L101)支持减少焦点变化时冗余工作的方向。本次只落实已确认的频道行重绑问题，保留 Fragment / ViewBinding / SurfaceView。其航拍文件预取、自动降档、HTTPS 转 HTTP、Compose 玻璃和屏保多实例管理不适合直接迁移。更早的包体研究固定在另一提交，见 [Aerial 参考评估](2026-10-27-aerial-tv-assessment.md)，不能把旧包体或作者性能数字当成本次收益。

## 验证

| 层级 | 本次结果 |
| --- | --- |
| 先复现再修复 | 最初新增的 5 项状态回归测试在旧实现上失败，修复后通过；随后补充首台、空列表、抵消和取消边界。 |
| JVM / Android 单元测试 | `testDebugUnitTest :core:model:test :source:api:test` 任务通过；29 个报告共 153 项，失败/错误/跳过均为 0，含 30 项 PlayerViewModel 测试。 |
| 构建 | `:app:assembleDebug :app:assembleDebugAndroidTest` 通过。 |
| cayin 设备 | Android 14 / API 34；新增 3 项 ChannelAdapter 测试、1 项真实 PlayerActivity 切台测试通过（9.468 秒）。 |
| 快切与画面 | 同一主线程内的按钮混合连按，以及 Android CHANNEL_UP/DOWN 事件，均收敛到预期频道；自制 MP4 经本地 HTTP 和真实 IPTV 源链路播放，确认 320×240、进度推进及 SurfaceView 非黑多色像素。 |
| 生命周期 | 快切前后保持同一个 PlayerEngine；关闭 PlayerActivity 后 PlaybackManager 不再持有该实例。该断言不等于所有换台均复用同一个底层 MediaCodec。 |
| 央视官方网络复测 | 同一 APK 上 CCTV-1 持续播放约 80 秒后，依次切到 CCTV-2、5、13；均确认 1280×720、播放进度、音轨选择与原生 SurfaceView 画面，1 项测试通过（158.454 秒）。首次运行在切 CCTV-2 时超时；只补充状态诊断和按钮有效性断言后复测通过，未改生产代码或降低原断言，首次超时原因尚未确认。 |

Debug APK：`JuYing_debug_0.1.0_20261027.apk`，78,059,485 bytes。SHA-256：`5dc69bae6499292e3f8e99db60e8c32f36c11e9ab64462fb0ad2709045fc31c3`。安装包与设备 `base.apk` 哈希一致，保留应用数据；新增测试只删除自己的临时源和历史。

## 审查与边界

标准与需求两路独立审查发现的首台按键、查询取消提示、空列表恢复问题已修复并补测试；最终限定本轮变更复核未发现阻断项。Jev 实际调用模型为 `jev-1.14.0`，完成两轮辅助判断；它对“待切基点上的正反抵消”仍给出不确定值（0.46），因此未把概率当作通过结论，该路径由确定性单测和人工状态推演确认。

未测量换台首帧 P95/P99、帧率或 PSS 的前后差值，不宣称具体毫秒提升；未进行物理遥控器或声音听验，未复测 qytech6666、手机和平板。第三方网络、解析器和解码器速度仍影响首帧时间。

## 2026-10-28：央视超时复现与测试判据修复

本轮在同一 cayin（Android 14 / API 34）、同一主 APK 上，确认了直播测试的超时误报。主 APK SHA-256 仍为上文的 `5dc69bae6499292e3f8e99db60e8c32f36c11e9ab64462fb0ad2709045fc31c3`；未修改或重装播放器产品代码。

旧判据要求 `positionMs >= 3000`。Media3 的直播位置相对滑动窗口起点，窗口刷新时可以回退，并非累计播放时长，见 [Media3 直播位置说明](https://developer.android.com/media/media3/exoplayer/live-streaming#detecting_and_monitoring_live_playbacks)。本机同期抓到的官方播放列表为 3 段、每段 4 秒，刷新时窗口前移 4 秒；该主机采样仅辅助解释窗口行为，不等同设备失败时的精确播放列表。

干净复现中，目标始终为 CCTV-1，无待切、解析错误或播放错误；约 4.915 秒首次取得有效 Surface 画面，累计采到 52 次有效画面、51 次画面变化和 14 次位置回退，旧门槛仍在约 60 秒超时。这足以确认本轮存在测试误报。此前一轮受未预期频道变化影响，另一轮 USB 断开，均不用于完整验收；10 月 27 日首次 CCTV-2 超时缺少同等连续观测，不能追溯断定完全同因。

修复限于 [CctvNativeHdTest](../../app/src/androidTest/kotlin/com/flytech/juying/CctvNativeHdTest.kt)：复用清晰度测试已有的连续进展判断，每 200ms 采样，要求连续至少 5 次合理正增量、累计至少 1000ms；位置回退、停滞、不合理跳跃或目标状态不符时重新计数。保留目标频道、无待切/错误/网页回退、高清、音轨选择、原生线路、Surface 有效画面和默认 80 秒长播检查。增加 `cctvZapRounds` 以重复切台路径；`cctvSkipLongHold=true` 仅供显式诊断快跑，不能代替完整验收。

| 本轮验证 | 结果 |
| --- | --- |
| 测试 APK 构建 | `:app:assembleDebugAndroidTest` 通过；测试 APK SHA-256：`855376b7b186591fabca327fa0a9ec0ea449bf6463deb499f323d23e5b1667de`。 |
| 五轮连续切台与长播 | CCTV-1 → 2 → 5 → 13，下一轮返回 CCTV-1，共 19 次换台，包含默认 80 秒长播；24 次状态/画面检查全部通过，耗时 187.120 秒。各次均为 1280×720、选中音轨且 Surface 有效；通过时的位置均小于 3000ms。 |
| 共享判据回归 | 默认 720p → 手选 360p / 480p / 576p → 手选 720p → 自动；6 阶段进展和 Surface 检查通过，耗时 25.097 秒。 |
| 审查 | Standards / Spec 两路独立审查均无阻断项；Jev（实际 `jev-1.14.0`）支持先采样、再做测试局部修复，未把概率作为真机通过依据。 |

完整切台命令（不传跳过长播参数）：

```powershell
adb -s 7c9349cc5027c4c7 shell am instrument -w -r -e class 'com.flytech.juying.CctvNativeHdTest#officialLiveUsesNativeSurfaceRefreshesAndZapsChannels' -e cctvLiveNative true -e cctvZapRounds 5 com.flytech.juying.test/androidx.test.runner.AndroidJUnitRunner
```

本地证据位于被忽略的 `build/cctv-switch-timeout/`：`probe-original-gate-3.log`、`fixed-5-rounds-longhold.log`、`fixed-quality.log` 与两路审查报告。`readyMs` 表示目标状态就绪，`confirmedMs` 表示通过进展检查，均不是精确首帧耗时；没有据此宣称换台性能提升。未重跑无关全量单测，未进行物理遥控器、声音听验或其他设备复测；有限轮次不能排除未来网络或解码器问题。
