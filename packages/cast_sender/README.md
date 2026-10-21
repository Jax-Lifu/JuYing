# juying_cast_sender

DLNA 投屏发送端 (DMC) 核心包（遵循 Section 5.7 规范）。

## 核心职责 (What)
- 远端 MediaRenderer 设备发现与手动 IP 兜底连接 (CAST-01)。
- SOAP 控制指令发送（Play / Pause / Seek / Stop / Volume / GetPositionInfo）(CAST-02)。
- 设备兼容性画像库 (DeviceProfile) 动态匹配与 MIME 降级 (CAST-04)。

## 设计动机 (Why)
遵循 ADR-003 与协议 UI 分离原则，纯 Dart 实现投屏发送逻辑，方便脱离界面进行抓包回归测试。
