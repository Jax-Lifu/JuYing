# ADR-003: DLNA / UPnP 协议栈首选 Dart 自研实现

## 状态
已接受 (Accepted)

## 日期
2026-10-20

## 背景与上下文
聚映需要支持局域网 DLNA / UPnP 双角色架构：
- 移动端 / 桌面端作为 DMC (Digital Media Controller) 发射端：发现设备、推送媒体、遥控播放进度与音量。
- 大屏端 / 桌面端作为 DMR (Digital Media Renderer) 接收端：被手机主流 App 发现、响应 AVTransport / RenderingControl 控制指令。
可选项包括：Dart 自研实现、使用现有 pub 库（dart_cast）、引入 Rust 原生库（如 rusty_dlna + flutter_rust_bridge）、或复用 C++ (Platinum / gmrender-resurrect)。

## 决策
首选基于纯 Dart 自研实现 DLNA / UPnP 协议栈（SSDP 组播发现、SOAP 动作调用与 XML 编解码、GENA 事件通知），参考 `dart_cast` 与 `rusty_dlna` 的设计经验。

## 原因分析与权衡
1. **跨平台构建复杂度最低**：
   - 纯 Dart 实现无需引入复杂跨平台 C/C++/Rust 原生编译链路与工具链（如 NDK, CMake, Cargo），杜绝 ABI 动态链接兼容问题。
2. **调试与迭代速度快**：
   - 协议与 UI 处于同语言环境，异常堆栈清晰，易于编写脱离 Flutter 界面树的控制台单元测试与抓包回放测试。
3. **架构解耦**：
   - 协议代码下沉到独立协议层，只认标准领域会话 `PlaybackSession`，不直接耦合播放器 UI。

## 何时重审
当长稳测试（7天常驻运行）中发现 DMR 接收端在处理高并发 SSDP 报文或极端网络波动时引发 Dart Isolate 开销瓶颈、或内存出现非预期增长时，评估将协议核心迁移至 Rust。
