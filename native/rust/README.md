# Rust 原生协议核心工作区 (可选，Optional)

根据《聚映项目指导文档 v0.1》第 6.1 节规范与 ADR-003：
- DLNA / UPnP 协议栈首选纯 Dart 实现。
- 若未来 DMR 接收端在处理极端高并发报文或长时间运行时出现 Dart Isolate 性能瓶颈，可将底层协议调度核心迁移至此 Rust 工作区，通过 `flutter_rust_bridge` 与上层交互。
