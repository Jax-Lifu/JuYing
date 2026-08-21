# 聚映 (JuYing) 核心架构与工程约束规范

## 1. 领域模型与数据隔离原则 (Animeko Pattern)
- **实体身份与播放候选解耦**：全局媒体模型划分为规范实体 `MediaItem` 与具体源候选 `PlaybackCandidate`，禁止来源特有字段污染核心实体。
- **搜索请求 Epoch 机制**：全局跨源并发检索必须使用防抖（Debounce 300ms）与版本化 `EpochId` / `CancelToken`，旧请求响应严禁覆盖新结果。

## 2. 播放内核与硬解降级原则 (FongMi / Kazumi Pattern)
- **统一播放内核**：所有平台统一使用 `media_kit` (libmpv 底层) 驱动。
- **硬解故障自愈**：硬解渲染异常时必须自动捕获并平滑降级至软解，禁止黑屏或应用崩溃。
- **音频/字幕时序校准**：播放器必须提供毫秒级音轨延迟与字幕延迟微调接口。

## 3. 网络与 IPTV 协议解析原则 (Guovin / iptv-org Pattern)
- **IPv4 / IPv6 双栈探测**：启动时自动检测网络环境，智能提升可达协议（如 IPv6 专属直播源）的优先级。
- **请求头动态注入**：严格支持 `#EXTVLCOPT`、`#EXTHTTP` 及 URL 后缀规则（`User-Agent`、`Referer`、`Origin`、`Cookie`）。
- **3秒故障无感换源**：直播流卡顿 >3000ms 或 HTTP 报错时，触发熔断器自动换线。

## 4. 局域网 NAS 协议与流桥接原则
- **禁止私有 Socket 直接喂流**：Samba (SMB) / NFS 必须通过内置 `127.0.0.1` 微型 Loopback HTTP Proxy 转换为标准 206 Partial Content Range 分块流。
- **安全凭据存储**：NAS 账号密码与 Token 仅存入平台安全加密存储（`flutter_secure_storage`），禁止明文日志或明文持久化。

## 5. TV 遥控器与交互适配原则
- **TV Focus First**：大屏页面所有可交互元素必须具备明确的 `FocusNode`，焦点必须具备高对比度发光外框与 `1.05x` 呼吸缩放动效。
- **远程配置门户**：支持在局域网暴露 `http://ip:port` 网页并展示二维码，方便手机/电脑直接推送直播源与 TVBox 配置。

## 6. 主题与国际化规范
- **禁止硬编码颜色**：所有组件必须通过统一的 `AppThemeColors` Token 消费颜色，确保 VS Code Dark+、One Dark Pro、Monokai Pro 等主题一键动态热切。
- **动态多语言**：文案全量接入 i18n 字典，支持运行时即时热更新。
