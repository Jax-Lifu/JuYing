# ADR-007: 仓库分层规范与严格自上而下单向依赖

## 状态
已接受 (Accepted)

## 日期
2026-10-20

## 背景与上下文
随着协议解析器（M3U、XMLTV、TVBox、SMB、WebDAV、DLNA、AirPlay）与多平台特性的持续增长，如果所有业务、协议与 UI 混在一个目录，会导致跨平台调试困难、无法脱离 Flutter 界面独立运行测试，并容易产生循环依赖与难以维护的泥球系统。

## 决策
采用清晰分层架构，代码组织按职责隔离，依赖关系自上而下严格单向流动：
- **依赖方向**：`core` → `net / storage` → `player_engine / source_providers / epg / discovery / proxy_server` → `cast_sender / receiver` → `apps / features`。
- **协议层与 UI 层分离**：协议实现代码必须能脱离 Flutter 界面框架单独在纯 Dart 环境中运行单元测试与抓包夹具回放。
- **抽象反转**：UI 层只认领域模型（`MediaItem`, `Channel`, `PlaybackSession`）与统一服务契约（`SourceProvider`, `PlayerEngine`, `ReceiverService`），严禁 UI 直接碰 C-FFI 或平台底层通道。

## 原因分析与权衡
1. **可测试性**：协议层解析、网络重写、SOAP 报文编解码均具备独立的纯 Dart 单元测试，测试速度提升数倍。
2. **多端复用**：无论是本地用户操作、DLNA 远端推送还是 AirPlay 请求，都统一封装为 `PlaybackSession` 提交给统一播放中枢，界面只需订阅播放状态。
3. **分包演进路径明确**：初期可在主仓以 Clean Architecture 特性目录维护，随着协议独立性成熟，可平滑拆分为 Melos 多包工作区。

## 何时重审
长期生效。
