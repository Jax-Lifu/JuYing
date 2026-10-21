# juying_proxy_server

本地微型 HTTP Range 代理服务包（遵循 ADR-006 架构决策）。

## 核心职责 (What)
- 在本地回环 `127.0.0.1:9978` 或局域网私有网卡暴露标准 HTTP 206 Partial Content 分块流。
- 动态注入防盗链请求头 (`User-Agent`, `Referer`, `Cookie`)。
- HLS 清单与密钥地址改写。
- 生成具备 TTL 生存时间与防枚举特性的 UUID v4 一次性令牌。

## 设计动机 (Why)
智能电视等 DLNA 渲染端通常不支持发送自定义 HTTP 请求头，且无法直连 Samba/WebDAV 等私有协议。通过本地代理桥接，使远端设备以标准 HTTP Range 方式平滑拉流。
