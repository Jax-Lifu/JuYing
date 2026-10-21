# ADR-013: 播放引擎分期交付策略：libmpv 通用首发，Media3 杜比第二引擎后置

## 状态
已接受 (Accepted) - 2026-10-21 (修订 ADR-002 之交付节奏)

## 背景与上下文
在指导文档 v0.2 与 ADR-002 中，为满足 Android TV 端 4K/HDR/杜比视界（Dolby Vision）与音频直通的高阶需求，规划了 libmpv + Media3 (ExoPlayer) 双引擎架构。
但在工程落地评估中发现，在 Flutter 中自研生产级 Media3 原生纹理渲染与生命周期桥接开发开销极大（3~4 周），且极易在低端 TV 盒子上出现 PlatformView 性能掉帧与黑屏故障。若将其作为首个垂直切片的硬性阻断项，将严重拖延核心功能落地。
同时，`media_kit` (libmpv + MediaCodec 硬解) 在 Windows 与 Android TV 上已能成熟覆盖 4K H.264/HEVC/AV1 与 HDR10。

## 决策
1. **MVP 统一单引擎首发**：
   - 首个垂直切片在 Windows 与 Android（含手机、平板、Android TV）上统一采用 `media_kit` (`MpvEngine`) 承载，以最短路径实现 4K、HDR10、高码率直播与 NAS 媒体流畅播放与遥控器交互。
2. **保持抽象层架构解耦**：
   - 上层 UI 与业务一律面向 `PlayerEngine` 统一接口编程，底层保留 `EngineCapabilities` 与双引擎调度槽位。
3. **Media3 作为高阶专项后置**：
   - 将 Media3 插件集成与杜比视界 Profile 5/8 硬件直通降级为 P1 专项（PoC-10），待基础切片稳定运行后再引入，避免阻塞交付。

## 权衡与后果
- **收益**：避免了在 MVP 阶段陷入 Android 原生媒体管道开发的泥潭，大幅缩短端到端全链路跑通周期。
- **代价**：首发版本在部分仅支持杜比视界私有色彩映射且缺少回退层的边缘片源上可能无法呈现最佳色调。
