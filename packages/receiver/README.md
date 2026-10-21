# juying_receiver

DLNA 接收端 (DMR) 核心服务包（遵循 Section 5.8 规范）。

## 核心职责 (What)
- 响应 SSDP M-SEARCH 广播与生成设备描述 XML (DMR-01)。
- 响应 AVTransport 与 RenderingControl 控制动作 (DMR-02)。
- 支持 GENA 事件订阅与状态上报 (DMR-03)。
- 仅接受合法 http/https 地址，拒绝 file:// 等私有 scheme，支持白名单与配对 PIN (DMR-05)。

## 设计动机 (Why)
遵循 Section 5.8 与 ADR-003，支持将当前桌面或 TV 端作为渲染接收设备，被手机主流 App 投屏。
