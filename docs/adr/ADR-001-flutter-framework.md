# ADR-001: 选择 Flutter 作为主线跨平台 UI 框架

## 状态
已接受 (Accepted)

## 日期
2026-10-20

## 背景与上下文
聚映 (JuYing) 定位为面向家庭网络的跨平台聚合播放器，主力目标平台为 Windows 10/11 与 Android（含 Android 手机、平板及预留 Android TV）。
在跨平台技术选型阶段，主要对比了 Flutter 与 Tauri 2。

## 决策
选择 **Flutter (Stable)** 作为客户端主线 UI 与应用开发框架。

## 原因分析与权衡
1. **视频播放与硬件解码能力**：
   - Tauri 2 依赖系统 WebView 承载渲染与解码。在桌面与移动端，WebView 解码对 HEVC/H.265、AV1、FLV、TS、RTSP 以及 UDP/RTP 组播流的支持严重受限于平台 WebView 与底层系统支持，在低端盒子或旧版 Windows/Android 上极易出现黑屏或无法解码。
   - Flutter 能够通过 C-FFI（如 `media_kit`）直接操作原生底层渲染管线，通过 Direct3D 11 / MediaCodec 驱动原生播放内核，实现全平台统一的硬件解码加速与回退。
2. **大屏与 TV 交互支持**：
   - Flutter 具备完善的 FocusNode 与键盘/遥控器（D-Pad）焦点导航树，非常契合 10 英尺客厅大屏交互需求。
3. **生态与成熟度**：
   - Windows 与 Android 在 Flutter 中均为第一公民（Tier 1）支持，具备丰富的桌面与移动端原生扩展生态。

## 何时重审
当产品战略发生转变，转为以纯 Web 网页内容浏览为主且不再强依赖专业流媒体协议与原生解码时重审。
