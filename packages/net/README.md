# juying_net

统一网络通信层包。

## 核心职责 (What)
- 统一 HttpClient (Dio) 配置与超时控制。
- 文本编码自动探测（UTF-8, GBK, GB2312, UTF-8 BOM）。
- 代理路由、DoH (DNS over HTTPS) 与自签证书按源放行策略。

## 设计动机 (Why)
避免在各个源提供者中散落裸网络请求代码，统一注入防盗链、重试与证书处理策略。
