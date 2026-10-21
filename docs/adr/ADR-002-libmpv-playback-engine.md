# ADR-002: 采用 media_kit (libmpv) 为通用内核，并在 Android TV 上引入 Media3 双引擎架构

## 状态
已更新 (Updated) - 针对 Android TV 4K/HDR/杜比特性触发双引擎分工决策 (v0.2)

## 日期
2026-10-20

## 背景与上下文
跨平台多格式流媒体播放是聚映的核心业务，需要覆盖 HTTP(S)、HLS、DASH、FLV、MPEG-TS、RTSP、RTMP 以及本地多格式视频容器（MKV、MP4 等），并支持音轨/外挂字幕切换、硬件加速解码及平滑回退。
在指导文档 v0.2 中，TV 首个版本将 **4K、HDR 与杜比能力（杜比音频 AC-3 / E-AC-3 / Atmos 直通，以及杜比视界 Dolby Vision）** 列为必备能力（PLY-13 / R17 / PoC-10）。

## 决策
1. **默认与桌面主力**：在 Windows、Android 移动端和通用场景下，继续采用 `media_kit` (libmpv C-FFI) 作为跨平台默认播放引擎 (`MpvEngine`)。
2. **Android TV 第二引擎**：在 Android TV 上引入 Android 原生 `Media3` (ExoPlayer) 作为第二引擎 (`Media3Engine`)。
3. **双引擎协同调度**：
   - 直播流与杜比/HDR 码流优先由 `Media3Engine` 承载，以发挥电视芯片对 Tuner / MediaCodec 直通与杜比视界元数据的硬件解调优势；
   - 点播与冷门封装格式可由 `MpvEngine` 承载或互为故障回退，架构上参考 OwnTV 与 DreamPlayer 的分工模型。
4. **统一抽象层**：界面层一律通过 `PlayerEngine` 接口调用，屏蔽底层 libmpv 与 Media3 的异构实现。

## 原因分析与权衡
1. **格式与协议覆盖广**：
   - libmpv 继承 FFmpeg 完整格式栈，对 TS、FLV、RTSP 和复杂 ass 字幕表现优异。
2. **电视大屏硬件生态适配**：
   - Android TV 设备芯片（如晶晨 Amlogic、联发科 MTK）的原厂固件对 Media3 / ExoPlayer 提供了深度硬件认证（如 Dolby Vision Profile 5/8 直通、HDMI eARC 源码直通）；libmpv 在部分 TV 芯片驱动上的杜比视界着色器映射可能存在色偏或掉帧。
3. **双引擎弹性**：
   - 当一种引擎遇到芯片解码器卡死（MediaCodec dead）或格式不兼容时，可自动切换到另一引擎重试，极大提升客厅大屏播放成功率。

## 何时重审
如果未来 libmpv 在 Android TV 上完善了原生 Dolby Vision 与 Audio Passthrough 硬件管道，且实测效果与 Media3 相同，可评估精简为单引擎。
