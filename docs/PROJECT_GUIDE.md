# 聚映项目指导文档

> 版本 v0.2｜2026-10-20｜状态：规划阶段，尚未编码；已按 Q1–Q11 的回答更新 目标平台：Windows 10/11 + Android 9+（手机、平板、Android TV，首个版本均需支持） 主线方案：Flutter + media_kit（libmpv）+ 本地网络服务层；开源发布，AI 辅助开发

## 0. 阅读说明

- 优先级：**P0** = MVP 必须；**P1** = 首个正式版应有；**P2** = 后续迭代。
- ⚠️ = 待决策，或必须先做技术验证（PoC）后才能承诺。
- 需求编号（如 PLY-01）在 issue、测试用例、提交信息里统一沿用。
- 本文是活文档：每个里程碑结束后回头修订第 9 章（风险）和第 11 章（待决问题）。
- 文中的包名、仓库和版本都是候选项，落地前以官方仓库当时的维护状态、许可证和平台支持为准。

## 1. 项目概述

### 1.1 定位

面向家庭网络的跨平台聚合播放器：把 IPTV 直播、点播源（含 TVBox 配置）、NAS 与本地媒体放进同一个播放界面；既能把内容投到局域网电视，也能作为 DLNA / AirPlay 接收端被手机和电脑投屏。

### 1.2 典型场景

| 场景 | 设备 | 行为 |
| --- | --- | --- |
| 客厅大屏 | Windows 接电视；Android TV / 盒子（首个版本即支持） | 遥控器或键鼠看直播，被手机投屏 |
| 书桌 | Windows | 看直播、点播，播放 NAS 资源，常驻为接收端 |
| 手机 | Android | 随时观看，把内容推到电视 |

### 1.3 设计原则

1. 播放内核统一（libmpv），两端行为一致。
2. 内容与应用解耦：应用不内置任何源，默认源只是用户可编辑、可删除的预设。
3. 协议层与 UI 层分离，协议代码必须能脱离 Flutter 单独测试。
4. UI 从第一天起按“响应式 + 焦点导航”设计；手机与 Android TV 同为首个版本的目标，视觉语言参考 Apple 风格（见 5.11）。
5. 先打通最小闭环，再扩协议；高风险项（AirPlay、TVBox jar 爬虫）先做 PoC。

### 1.4 非目标（当前阶段）

- 不提供或运营任何内容服务器、账号体系和自有云同步服务（跨设备同步仅支持用户自配 WebDAV，见 APP-12）。
- 不做 BT/磁力下载；离线缓存下载放到 P2 再议。
- 不做 iOS / macOS / Linux（架构不排斥，但不承诺、不测试）。
- 不直连各家网盘（通过 Alist 等的 WebDAV 间接支持）。
- 不做服务端转码（仅在必要时于本机转封装）。

## 2. 需求清单

### 2.1 播放核心（PLY）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| PLY-01 | 基于 libmpv 播放 HTTP(S)、HLS、DASH、FLV、TS、RTSP、RTMP 与本地文件 | P0 |
| PLY-02 | 硬解优先，失败自动回退软解；Windows 用 D3D11 系硬解，Android 用 MediaCodec | P0 |
| PLY-03 | 播放/暂停/拖动/倍速/音量/静音/全屏 | P0 |
| PLY-04 | 音轨、字幕轨切换；外挂字幕（srt/ass/vtt）加载 | P0 |
| PLY-05 | 字幕样式、在线字幕搜索 | P1 |
| PLY-06 | 断点续播、播放历史 | P0 |
| PLY-07 | 每源可配置请求头（UA/Referer/Cookie）与代理 | P0 |
| PLY-08 | 缓冲策略可配置；断线重连 | P0 |
| PLY-09 | 画面比例、旋转、亮度/对比度 | P1 |
| PLY-10 | 画中画（Android）、后台音频、睡眠定时 | P1 |
| PLY-11 | 播放列表、连播、循环、随机 | P1 |
| PLY-12 | 诊断浮层：码率、解码器、丢帧、缓冲 | P1 |
| PLY-13 | 4K、HDR 与杜比（杜比音频直通与杜比视界均需支持，在目标设备上验证）、帧率匹配：TV 首个版本必备 | P0 ⚠️ |

### 2.2 直播 / IPTV（LIVE）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| LIVE-01 | 导入 M3U/M3U8 与 TXT（频道,URL 分组格式）源，支持 URL 与本地文件，自动识别编码 | P0 |
| LIVE-02 | 使用官方公开网址作为 CCTV 默认源（已接入），用户可编辑、可删除（见 3.5 合规） | P0 |
| LIVE-03 | 分组、搜索、收藏、最近观看、台标 | P0 |
| LIVE-04 | 同频道多线路，手动切换 | P0 |
| LIVE-05 | 线路测速、失败自动换线、线路权重持久化 | P1 |
| LIVE-06 | EPG（XMLTV，含 gz）：当前/下一节目、节目单页 | P1 |
| LIVE-07 | 订阅管理：定时更新、失败保留旧缓存、导入导出 | P1 |
| LIVE-08 | 快速换台：遥控器上下键、数字键、频道浮层、预热相邻频道（TV 首个版本必备） | P1 |
| LIVE-09 | 回看/时移（catchup 模板） | P2 ⚠️ |
| LIVE-10 | UDP/RTP 组播（含 udpxy 代理形式） | P2 |
| LIVE-11 | Xtream Codes 账户 | P2 |

### 2.3 点播源与 TVBox（VOD）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| VOD-01 | 点播源抽象：分类/搜索/详情/选集/播放地址解析 | P1 |
| VOD-02 | TVBox 配置导入（URL/文件），解析 sites、lives、parses、wallpaper 等字段 | P1 |
| VOD-03 | CMS 接口类站点 | P1 |
| VOD-04 | JS 类爬虫（QuickJS 沙箱） | P1 ⚠️ |
| VOD-05 | TVBox 配置内的直播源自动导入到 LIVE | P1 |
| VOD-06 | 源健康检查；当前平台不支持的站点置灰并说明原因 | P1 |
| VOD-07 | Jar 类爬虫：用 Dart 重新实现（逐站点移植，见 5.9）；Android 可选原生加载 DEX 兜底 | P1 ⚠️ |
| VOD-08 | 解析接口（parses）与嗅探 | P2 ⚠️ |
| VOD-09 | 多仓 / 源列表导入：一个地址包含多个配置，可选择其一或合并；列表里的单个配置失效不影响其他 | P1 |

### 2.4 本地与 NAS（LIB）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| LIB-01 | 本地文件/文件夹浏览与播放 | P0 |
| LIB-02 | SMB（SMB2/3）浏览与播放；大文件 Seek 性能先验证 | P0 ⚠️ |
| LIB-03 | WebDAV（含 Alist） | P0 |
| LIB-04 | 同目录外挂字幕自动匹配 | P1 |
| LIB-05 | FTP/SFTP | P2 |
| LIB-06 | 断线重连、Range 优化（MKV 尾部索引） | P1 |
| LIB-07 | NFS（Windows 与 Android 的客户端方案先做 PoC，见 PoC-7） | P1 ⚠️ |
| LIB-08 | Jellyfin（Emby/Plex 视情况） | P2 |
| LIB-09 | 元数据刮削（TMDB）、海报墙、剧集聚合 | P2 |
| LIB-10 | 作为客户端浏览 DLNA 媒体服务器 | P2 |

### 2.5 DLNA 发送端（CAST）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| CAST-01 | SSDP 发现局域网渲染设备，并提供手动输入 IP 兜底 | P0 |
| CAST-02 | 推送 URL 并控制：播放/暂停/Seek/音量/停止/进度查询 | P0 |
| CAST-03 | 本地代理出口：为电视提供可访问的 URL（本地文件、NAS、需请求头的源） | P0 |
| CAST-04 | 兼容性：DIDL-Lite 元数据、MIME、Range；设备兼容性画像库 | P1 |
| CAST-05 | 投屏时手机/电脑当遥控器，进度同步 | P1 |
| CAST-06 | 转封装兜底（电视不支持的容器/音轨） | P2 ⚠️ |
| CAST-07 | Chromecast / AirPlay 发送端 | P2 |

### 2.6 DLNA 接收端（DMR）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| DMR-01 | 作为 MediaRenderer 被发现（SSDP 广播 + 设备描述 XML） | P1 |
| DMR-02 | 响应 AVTransport / RenderingControl / ConnectionManager 动作 | P1 |
| DMR-03 | 事件订阅（GENA）与状态上报 | P1 |
| DMR-04 | 来源 URL 交给播放内核，读取 DIDL 标题与封面 | P1 |
| DMR-05 | 设备名称、开关、来源白名单 | P1 |
| DMR-06 | Android 前台服务 + MulticastLock 保活 | P1 |
| DMR-07 | Windows 托盘常驻、开机自启、防火墙引导 | P1 |

### 2.7 AirPlay 接收端（APL）——整体需先做 PoC ⚠️

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| APL-01 | mDNS 广播 AirPlay 服务 | P1 ⚠️ |
| APL-02 | 音频接收（ALAC/AAC），默认开启 | P1 ⚠️ |
| APL-03 | 屏幕镜像（H.264/H.265），默认关闭，用户手动开启 | P2 |
| APL-04 | 视频投放（HLS 交接），取决于所选实现是否支持 | P2 ⚠️ |
| APL-05 | PIN 配对与访问控制 | P2 |

### 2.8 应用通用（APP）

| 编号 | 需求 | 级别 |
| --- | --- | --- |
| APP-01 | 源管理中心：直播源、点播源、NAS 共享的统一入口 | P0 |
| APP-02 | 响应式布局：手机、平板、桌面窗口、电视横屏 | P0 |
| APP-03 | 设置：播放、网络、外观、字幕、快捷键 | P0 |
| APP-04 | Android TV 焦点导航与遥控器适配（首个版本必备） | P0 |
| APP-05 | 桌面特性：置顶小窗、托盘、全局媒体键、系统媒体控制（SMTC） | P1 |
| APP-06 | 国际化：简中、繁中、英 | P1 |
| APP-07 | 配置导入导出、备份恢复 | P1 |
| APP-08 | 更新检查（GitHub Releases 或自托管 JSON） | P1 |
| APP-09 | 日志导出、崩溃日志（本地优先，上传可选） | P1 |
| APP-10 | 首次引导：添加源、扫码导入、局域网推送配置 | P1 |
| APP-11 | 家长控制 / PIN | P2 |
| APP-12 | WebDAV 配置同步：用户自配 WebDAV，同步源配置、收藏、历史与设置；凭据加密后再同步，冲突按时间戳合并并保留备份 | P1 |
| APP-13 | Apple 风格设计语言：统一设计令牌、毛玻璃与动效，并提供低性能模式（见 5.11） | P0 |

### 2.9 非功能需求（目标值，需基准测试后校准）

| 维度 | 目标 |
| --- | --- |
| 起播 | 直播切台首帧 ≤ 2 s（良好网络），点播首帧 ≤ 3 s |
| 稳定 | 连续播放 24 h 无崩溃、内存无持续增长；接收端常驻 7 天可用 |
| 资源 | 1080p 直播：Android 中端机常驻内存 ≤ 300 MB；Windows 硬解下 CPU 占用 ≤ 10% |
| 兼容 | Android 9+（minSdk 28，含 Android TV），arm64-v8a 为主、兼顾 armeabi-v7a；Windows 10 及以上 x64 |
| 包体 | Android 单 ABI ≤ 50 MB（含 libmpv，待实测） |
| 可维护 | 协议层、解析层有单元测试；关键协议有抓包回放夹具 |
| TV 媒体能力 | 4K、HDR 与杜比（杜比音频直通与杜比视界均需支持，在目标设备上验证），以目标设备清单与真机结果为准 |

## 3. 你可能没考虑到的内容

### 3.1 产品与体验

- **空状态引导**：没有任何源时界面是空的，必须有“添加源 / 导入配置 / 扫码”的引导，否则首次体验像一个空壳。
- **换台速度决定直播体验**：预热相邻频道、复用解码器实例、缓冲预设；这是 IPTV 应用被诟病最多的点。
- **频道名归一化**：CCTV-1、CCTV1、央视一套、CCTV-1 综合要能合并成同一频道，需要别名表与规范化规则，EPG 匹配同样依赖它。
- **源失效是常态**：对失败原因分类（DNS、403、超时、证书、格式不支持、被限速）并给出可读提示，而不是一个“播放失败”。
- **IPv6**：不少源只有 IPv6，需验证两端在双栈、纯 IPv4、纯 IPv6 下的行为。
- **息屏与省电**：Android 息屏音频、电池优化白名单引导；Windows 播放时阻止休眠。
- **10 英尺 UI**：大屏字号、焦点高亮、遥控器按键映射（频道加减、数字键、菜单、返回）要单独设计，不能只是把手机界面放大。
- **无障碍**：至少保证系统字体缩放不破版。

### 3.2 协议与网络

- **本地代理的安全边界**：只绑定局域网网卡、随机端口、带一次性 token，避免被同网段其他设备当成开放代理；限制可代理的目标地址，防 SSRF。
- **电视拉流不带请求头**：必须经代理转发；代理要支持 Range、HEAD、keep-alive，并能重写 HLS 清单（相对/绝对地址、密钥地址）。
- **DLNA 兼容性长尾**：各品牌设备在设备描述、DIDL-Lite 必填字段、protocolInfo、`contentFeatures.dlna.org` 响应头、时间格式、SetNextAVTransportURI 上差异很大；建立“设备画像”配置，并用抓包夹具做回归。
- **多网卡环境**：虚拟机、VPN、WSL、热点会让 SSDP/mDNS 选错接口，需要网卡选择设置。
- **组播不通是高频问题**：AP 隔离、访客网络、路由器关闭 IGMP/组播转发、Wi-Fi 省电；必须提供手动输入 IP 的兜底与网络诊断页。
- **SSDP 端口占用**：同机其他 DLNA 软件可能占用 1900 端口，需端口复用并正确加入组播组。
- **明文 HTTP**：大量 IPTV 源是 http，Android 默认限制明文流量，需配置 network security config。
- **证书与 DNS**：自签/过期证书源（默认拒绝，可按源放行并提示）；部分源依赖特定 DNS，提供 DoH 选项。
- **文本编码**：M3U/TXT 常见 GBK、UTF-8 BOM，需自动检测。
- **EPG 时区偏移**：处理 tvg-shift 与不同时区的 XMLTV。
- **UPnP 事件订阅**超时续订与断线重订阅。

### 3.3 平台适配

**Android**

- 前台服务：Android 14 起前台服务必须声明类型；Android 13+ 需要通知权限；接收端保活依赖前台服务。
- MulticastLock：收发组播需要申请，息屏后需持有。
- 国内 ROM 的后台限制与自启动权限，需要引导用户设置。
- 存储访问：SAF / 分区存储，Android 11+ 的外部存储限制。
- 画中画、折叠屏与平板的窗口尺寸变化。
- TV 适配：leanback 声明、无触摸、焦点、Banner；低端盒子的 HEVC/4K 解码能力差异；多 ABI。

**Windows**

- 分发形态：安装包（Inno Setup / NSIS 或 MSIX）与便携 zip 两种都要提供；便携版数据放在程序目录旁，防火墙规则、开机自启等需要管理员权限的功能只在安装版自动配置，便携版改为首次使用时引导；SmartScreen 与代码签名。
- 防火墙：启用接收端时需要放行入站端口，首次使用要有引导。
- 系统集成：SMTC、全局媒体键、高 DPI、多显示器、HDR 开关。
- mDNS 与系统/Bonjour 服务的关系（AirPlay 相关）需实测。
- VC++ 运行库依赖、中文路径、UNC 路径、长路径。

### 3.4 安全与隐私

- DLNA 接收端默认关闭或“仅本人设备”，AirPlay 音频按你的决定默认开启（镜像需手动开启）；两者都建议提供来源白名单与配对 PIN。
- 接收端只接受 http/https 地址，拒绝 file:// 等 scheme，避免被用来读取本机文件。
- NAS 密码使用系统安全存储（Android Keystore / Windows 凭据存储）；配置导出时脱敏或加密。
- 第三方 JS 爬虫放入沙箱：禁用文件/进程访问，仅开放受控的 http/crypto/storage API，限制超时与内存；jar 类爬虫改用 Dart 重新实现后不再加载外部字节码，风险较低；若 Android 保留原生加载 DEX 的兜底，则默认关闭，需用户明确开启并警示。
- 日志脱敏：URL 里的 token、账号密码不得明文落盘。
- 依赖锁定版本并定期审计；原生库（libmpv、FFmpeg、UxPlay）记录来源与校验值。

### 3.5 合规与许可

- **内容**：应用不内置、不分发第三方内容；默认 CCTV 源使用官方公开网址（已接入），保持可编辑、可删除，并附免责声明与隐私政策。
- **分发渠道**：各应用商店对 IPTV/聚合类应用的政策不同，上架前逐一核对；国内可能需要自行分发。
- **FFmpeg / libmpv 许可**：项目开源后 GPL 构建也可接受，但仍建议优先 LGPL 并动态链接，保留日后调整许可证的余地；核对 media_kit 所带 libmpv 构建的许可证。
- **UxPlay（GPLv3）**：集成会使分发物受 GPL 约束。项目既然开源，这不再是障碍，但整个项目需以 GPL 兼容的协议发布（见 11.1）。
- **GPL/AGPL 参考项目**（Iris、DreamPlayer、Alist 等）项目开源后，可在遵守各项目协议（保留署名与版权声明、以兼容协议发布）的前提下参考甚至复用代码；复用前先逐个核对协议兼容性。
- **商标**：“AirPlay”“DLNA”是他人商标，描述性使用可以，但不要暗示官方认证；表述用“兼容 UPnP AV / DLNA 设备”。
- **编解码专利**：个人/开源分发一般风险较低，商业分发前需评估；杜比相关：据我所知，直通（把码流交给电视或功放解码）不涉及自行解码，而软解杜比音频、使用 Dolby 标识可能涉及授权，上架前核对。

### 3.6 工程化

- Monorepo + melos 管理多包；用 fvm 锁定 Flutter 版本。
- **抓包夹具**：用 Wireshark 抓各品牌电视与手机投屏的 SOAP/SSDP 交互，存成回放测试，是 DLNA 回归的核心资产。
- **真机矩阵**：电视品牌、Android 版本/ROM、Windows 版本，见第 10 章。
- **可观测**：结构化日志 + 环形缓冲 + 一键导出；播放失败使用统一错误码。
- **特性开关**：AirPlay、TVBox jar 等实验功能默认关闭，在设置的“实验室”里开启。
- **配置 schema 版本化**并提供迁移，避免升级后旧配置失效。

### 3.7 长期运营

- 预设源清单托管为独立 JSON，可远程更新（用户可关闭），源失效时无需发版。
- 反馈渠道、Issue 模板、FAQ（“局域网找不到设备怎么办”会是第一高频问题）。
- 兼容性数据库（设备画像）以社区贡献方式持续积累。

## 4. 总体架构

### 4.1 技术选型（候选，落地前核对最新状态）

| 领域 | 首选 | 备选 | 说明 |
| --- | --- | --- | --- |
| UI 框架 | Flutter（stable） | — | Windows、Android 都是一等平台 |
| 状态管理 | Riverpod | Bloc | 依赖注入与异步状态都好处理 |
| 路由 | go_router | auto_route | 深链接、嵌套导航 |
| 播放内核 | media_kit（libmpv） | Android Media3 + Windows libmpv；fvp | 格式覆盖广，两端行为一致 |
| 本地数据库 | drift（SQLite） | Isar | 频道、EPG、历史量大，需要索引与查询 |
| 设置存储 | shared_preferences | — | 简单键值 |
| 安全存储 | flutter_secure_storage | — | NAS 凭据 |
| 网络 | dio | http | 拦截器、取消、重试 |
| mDNS | bonsoir / multicast_dns | — | 候选，需在两端实测 |
| DLNA/UPnP | Dart 自研，参考 dart_cast、rusty_dlna | Rust 核心 + flutter_rust_bridge | ⚠️ 见 ADR-003 |
| AirPlay | UxPlay（C）经 FFI / JNI | 暂缓 | ⚠️ 先 PoC，许可证见 3.5 |
| SMB | smb_connect（纯 Dart）或 libsmb2 FFI | — | ⚠️ 大文件 Seek 需实测 |
| WebDAV | webdav_client | 自研 | 兼容 Alist |
| JS 引擎 | QuickJS（如 dart_quickjs、flutter_js） | — | 跑 TVBox JS 爬虫 |
| 桌面集成 | window_manager、tray_manager、hotkey_manager | — | 窗口、托盘、快捷键 |
| 系统媒体控制 | audio_service / 原生 MediaSession；Windows SMTC 插件 | — | 媒体键、锁屏控制 |
| 模型与序列化 | freezed + json_serializable | — | 不可变模型 |
| 日志 | logger + 文件滚动 | — | 统一脱敏过滤 |
| 工程 | melos + fvm | — | 多包管理、版本锁定 |
| CI/CD | GitHub Actions | — | Windows、Android 双构建 |
| NFS | 待 PoC：libnfs FFI、纯 Dart 实现或系统挂载 | 经 SMB / Alist 兜底 | ⚠️ 首个版本的主力协议之一，两端方案可能不同 |
| UI 风格 | Cupertino 组件 + ui_kit（设计令牌与少量自建组件） | 全量自绘 | 见 5.11 |
| 配置同步 | WebDAV（用户自配） | — | 见 APP-12 |
| TV 适配 | Flutter 焦点系统（FocusTraversalGroup、Shortcuts）+ leanback 声明 | — | 见 5.11 |

### 4.2 分层架构

依赖只能自上而下：界面层只认领域层与服务层的抽象接口，协议实现放在 packages，界面代码不直接碰 FFI 或平台通道。无论内容来自本地点击、DLNA 推送还是 AirPlay，都先变成一个播放会话，再交给播放引擎，这样界面只需订阅会话状态。

### 4.3 关键决策记录（ADR 摘要）

| 编号 | 决策 | 原因 | 何时重审 |
| --- | --- | --- | --- |
| ADR-001 | 选 Flutter，不选 Tauri 2 | 视频靠系统 WebView 解码，HEVC/AV1 与 FLV/TS/RTSP/组播等受设备限制；播放器需要原生解码与协议覆盖 | 产品转为以 Web 内容为主时 |
| ADR-002 | 播放内核用 libmpv | 格式、字幕、音轨、硬解覆盖好，两端同一内核 | 已触发：TV 首个版本要求 4K、HDR、杜比，Android TV 上引入 Media3 作为第二引擎（见 5.3） |
| ADR-003 | DLNA 先用 Dart 实现 | 迭代快，与 UI 同语言，可借鉴 dart_cast 等实现 | 接收端稳定性、并发或 Isolate 开销成为瓶颈时，迁到 Rust |
| ADR-004 | AirPlay 后置，先做 PoC | 协议非公开、依赖逆向实现，GPL 许可影响分发 | PoC 结论出来后 |
| ADR-005 | 应用不内置内容 | 合规风险、可维护性 | 不重审 |
| ADR-006 | 本地代理统一出口 | 投屏、需请求头的源、NAS 转发共用一套基础设施 | — |
| ADR-007 | Monorepo 分包 | 协议层可独立测试与复用 | — |
| ADR-008 | TVBox 先做 CMS 与 JS，jar 类爬虫用 Dart 重新实现（逐站点移植），Android 可选原生加载 DEX 兜底 | jar 是 Android 字节码，Dart 无法直接执行，只能重写或借助 JVM | 找到可靠的 JVM 方案时 |
| ADR-009 | 项目以 GPL-3.0 开源（已确认） | 可集成 UxPlay 等 GPL 组件，并复用 GPL 参考项目 | 确认许可证时（见 11.1） |
| ADR-010 | UI 以 Cupertino 组件为基础，ui_kit 提供设计令牌与必要的自建组件，手机、桌面、TV 共用 | 三端视觉一致，TV 焦点效果统一 | 低端设备性能不达标时降级 |
| ADR-011 | 手机与 Android TV 同一代码库、同一套 features，布局与焦点按设备形态适配 | 首个版本同时支持两者，避免分叉 | 共用结构明显限制 TV 体验时 |

### 4.4 运行时模型

- **UI isolate**：只做渲染与交互。
- **后台 isolate**：解析大型 M3U/XMLTV、线路测速、扫描 NAS 目录。
- **网络服务**（本地代理、DMR、SSDP）：Windows 在主进程内用独立 isolate 运行；Android 有两个方案 ⚠️：（A）原生 Kotlin 前台服务承载接收端协议，保活最稳，代价是协议要走原生层或写两遍；（B）后台 FlutterEngine 复用 Dart 实现，代码统一但保活更脆弱。建议在 PoC 阶段对比后决定。
- **统一入口**：本地点击、DLNA 推送、AirPlay 都生成一个 PlaybackSession 交给 PlayerController。

## 5. 核心模块设计

### 5.1 领域模型

| 实体 | 关键字段 | 说明 |
| --- | --- | --- |
| Source（源） | id、type、name、endpoint、headers、credential_ref、enabled、updated_at | 一个订阅或一个共享 |
| Channel（频道） | id、source_id、name、normalized_name、group、logo、tvg_id、lines | 直播频道 |
| Line（线路） | url、headers、label、score、last_ok_at、fail_count | 频道的一条可播放地址 |
| Program（节目） | channel_id、start、end、title、desc | EPG 节目 |
| MediaItem（媒体项） | ref、title、kind、cover、size、duration | 点播与 NAS 条目 |
| PlayableOption | url、headers、label、kind、timeout | 解析后可直接交给播放器的对象 |
| PlaybackSession | id、origin（local / dmr / airplay）、media、state、position | 运行时播放会话 |
| CastDevice | id、protocol、name、location、capabilities、profile_id | 投屏设备 |
| DeviceProfile | match 规则、quirks | 设备兼容性画像，见附录 |
| History / Favorite | media_ref、position、updated_at | 历史与收藏 |

### 5.2 源提供者接口

```dart
abstract class SourceProvider {
  String get type;
  Set<SourceCapability> get capabilities;   // live / vod / browse / search / epg
  Future<ValidationResult> validate(SourceConfig config);
  Stream<Channel> channels(SourceConfig config);                       // 直播类
  Future<Page<MediaItem>> browse(SourceConfig config, BrowseQuery query);
  Future<Page<MediaItem>> search(SourceConfig config, String keyword, {int page = 1});
  Future<MediaDetail> detail(SourceConfig config, MediaRef ref);
  Future<List<PlayableOption>> resolve(SourceConfig config, MediaRef ref);
}
```

规则：一种源一个实现；当前平台不支持的能力在 capabilities 中声明，由界面置灰；所有网络访问经统一的 HttpClient（注入请求头、代理、超时、证书策略）。

### 5.3 播放引擎抽象

```dart
abstract class PlayerEngine {
  Future<void> open(PlayableOption option, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> selectAudio(TrackId id);
  Future<void> selectSubtitle(TrackId? id);
  Stream<PlayerState> get state;          // 位置、时长、缓冲、播放中
  Stream<PlayerFailure> get failures;     // 统一错误码
  Future<void> dispose();
}
```

实现：MpvEngine 为默认；Media3Engine 随首个版本在 Android TV 上引入（4K、HDR、杜比需求；据我所知 Media3 在 HDR 与杜比视界直通上比 libmpv 成熟，需 PoC-10 验证）（⚠️，P1）。直播用 ExoPlayer、点播用 mpv 的双引擎分工，可参考 OwnTV、DreamPlayer 的做法。

### 5.4 本地代理服务

- **路由**：`/p/{token}` 透传；`/hls/{token}/...` HLS 重写；`/f/{token}` 本地或 NAS 文件，支持 Range。
- **能力**：注入请求头与 Cookie；Range / HEAD / keep-alive；HLS 清单重写（相对地址改写、密钥地址）；并发与超时控制；日志脱敏。
- **安全**：只绑定局域网地址；随机端口；一次性 token 且会过期；限制可代理的目标地址。
- **生命周期**：投屏或播放需要时按需启动，空闲超时后停止。
- **兜底**：电视不支持的容器可由代理做转封装 ⚠️（P2）。

### 5.5 线路管理与自动换源

状态流转：Idle → Opening → Playing。Opening 超过首帧阈值或报错，则标记该线路失败，按评分选下一条；全部失败时给出分类后的错误提示。

- **评分**：近期成功率、首帧耗时、卡顿次数；持久化到线路表；失败后进入冷却期。
- **测速**：后台对当前分组并发做 HEAD 或首个分片请求，限制并发与频率，避免被源站封禁。
- **手动优先**：用户手动选择的线路优先，并被记住。

### 5.6 EPG 与回看

- **数据流**：下载 XMLTV（含 gz）→ 后台 isolate 流式解析 → 入库（drift）→ 按 channel_id + 时间窗口查询。
- **频道匹配顺序**：tvg-id → 别名表 → 规范化名称（去空格与符号、统一数字写法）→ 模糊匹配（需用户确认）。
- **回看**：URL 模板由源配置提供，变量与格式沿用各面板或 Kodi IPTV Simple 客户端的约定，以实际源为准 ⚠️；开始与结束时间做时区修正。
- **体量控制**：只保留未来 N 天与过去 M 天的节目，定期清理。

### 5.7 DLNA 发送端流程

1. **发现**：SSDP M-SEARCH 搜索 MediaRenderer，拉取设备描述并缓存 controlURL；同时支持手动输入设备地址。
2. **准备**：判断直链电视能否直接访问；不能则经本地代理生成 URL。
3. **推送**：SetAVTransportURI（附 DIDL-Lite 元数据）→ Play。
4. **同步**：定时 GetPositionInfo / GetTransportInfo，或订阅事件；界面显示进度并可控制。
5. **降级**：失败时按设备画像换策略（换 MIME、关闭外挂字幕、走转封装）。

### 5.8 接收端（DLNA / AirPlay）

统一接口 ReceiverService：start / stop、状态、onIncomingSession(PlaybackSession)。

DLNA MediaRenderer 需要实现的服务与动作：

| 服务 | 动作 | 说明 |
| --- | --- | --- |
| AVTransport | SetAVTransportURI、SetNextAVTransportURI、Play、Pause、Stop、Seek、GetPositionInfo、GetTransportInfo、GetMediaInfo | 播放控制与状态 |
| RenderingControl | GetVolume、SetVolume、GetMute、SetMute | 音量控制 |
| ConnectionManager | GetProtocolInfo、GetCurrentConnectionIDs、GetCurrentConnectionInfo | 能力声明 |

另需支持事件订阅（GENA）与 LastChange 状态上报。

- **AirPlay**：以 mDNS 广播 AirPlay 相关服务（`_airplay._tcp`、`_raop._tcp`），由 UxPlay 类实现处理配对、镜像与音频；视频投放是否可用取决于所选实现 ⚠️。
- **安全**：DLNA 接收端默认关闭；AirPlay 音频按你的决定默认开启（建议限定局域网并可一键关闭），镜像默认关闭、需用户手动开启；均支持来源白名单与 PIN，只接受 http/https。
- **与播放器的关系**：收到推送 → 生成 PlaybackSession（origin 为 dmr 或 airplay）→ 播放器前置；结束后恢复原状态。

### 5.9 TVBox 兼容层

流程：导入配置 → 解析 sites、lives、parses 等字段 → 按站点类型分发给对应 provider → 做平台能力检查。

| 站点类型 | 做法 | Windows | Android |
| --- | --- | --- | --- |
| CMS 接口（XML/JSON） | 原生 HTTP 解析 | 支持 | 支持 |
| JS 爬虫（drpy 一类） | QuickJS 沙箱 + 受控宿主 API | 支持 ⚠️ | 支持 ⚠️ |
| Python 爬虫 | 不做 | 不支持 | 不支持 |
| Jar 爬虫 | Dart 重新实现：把常用 jar 站点的抓取逻辑移植为 Dart provider，共用解析工具沉淀为规则引擎 | 支持（Dart 移植版）⚠️ | 支持（Dart 移植版）⚠️；可选原生加载 DEX 兜底（默认关闭） |
| 解析接口与嗅探 | 暂不做 | — | — |

站点类型编号与字段以社区约定为准，上线前用 FongMi/TV 等主流实现的配置样本做兼容性测试。不兼容项在界面上置灰并写明原因，不要静默失败。

关于“用 Dart 实现 jar 类爬虫”：Dart 不能直接执行 jar（Android 的 DEX 字节码），所以要做的是重新实现，而不是加载。建议路径：

1. 先收集你要兼容的配置里实际用到的 jar 站点清单，确定移植范围。
2. 逐个分析其抓取逻辑（通常是 HTTP 请求、HTML 或 JSON 解析、播放地址解析），用 Dart 重写，把共用的解析工具和规则沉淀下来。
3. 每个站点一个 provider（或一条规则），带样本数据与回归测试，放在 tvbox/ports/。
4. 站点改版会导致失效，需要持续维护；也只对你有权访问的站点做兼容，并遵守其服务条款。

AI 辅助适合批量移植，但每个站点都必须用真实请求验证。

### 5.10 配置与存储

- **分层**：用户设置用版本化键值；源配置用带 schema_version 的 JSON；业务数据（频道、线路、节目、历史、收藏）用 SQLite；凭据放安全存储，配置里只保存引用。
- **位置**：Windows 用用户应用数据目录；Android 用应用私有目录；导出使用用户选择的位置。
- **迁移**：schema_version + 迁移器，启动时自动升级并先备份旧数据。

### 5.11 UI 与设计语言（Apple 风格，手机、桌面、TV 共用）

目标是参考 Apple 的设计语言：留白充足、大标题、层级清晰、圆角、半透明毛玻璃、柔和阴影和弹性动效，并在 Windows、Android 手机与 Android TV 上保持一致。

- **设计令牌**：颜色（浅色与深色）、字号阶梯、圆角、间距、模糊强度、动效曲线与时长，全部集中在 ui_kit，页面里不写死样式。
- **组件**：尽量复用 Flutter 的 Cupertino 组件，并套用统一设计令牌；Cupertino 没有或 TV 焦点表现不够的部分（TV 焦点卡片、毛玻璃播放控制条等）再自建。大标题导航栏、分组列表、分段控件、底部弹层、上下文菜单优先用现成组件，毛玻璃播放控制条自建。
- **手机**：底部标签栏；手势包括下滑关闭播放页、左右拖动调进度、上下滑动调音量与亮度。
- **桌面**：侧边栏 + 内容区，窗口自适应；键鼠快捷键与右键菜单。
- **电视**：参考 tvOS 的焦点表现，焦点项放大并带高光或阴影；十英尺布局并留出安全边距；遥控器键位映射（方向、确认、返回、菜单、频道加减、数字键）；所有可交互元素都必须可聚焦，且焦点顺序可预期。
- **性能**：毛玻璃（背景模糊）在低端 Android 与 TV 盒子上开销大，需要设置性能预算，并提供“低性能模式”，把模糊降级为纯色半透明；视频画面上叠加模糊层要特别谨慎。
- **深色模式与无障碍**：建议播放场景以深色为默认，遵循系统字体缩放与“减少动态效果”设置。
- **字体与图标的许可**：据我所知，SF Pro 字体和 SF Symbols 的许可限制在 Apple 平台使用，不应随应用分发。建议用各系统默认字体，或开源字体（如 Inter）；图标用开源图标库（如 Lucide、Phosphor，使用前核对许可证）。“参考风格”不等于复制 Apple 的素材、图标与商标元素。

## 6. 目录结构

### 6.1 仓库总览（monorepo）

```text
juying/
├─ apps/
│  └─ juying_app/                  # 唯一可运行的应用（Windows + Android）
│     ├─ lib/
│     │  ├─ main.dart              # 入口：初始化、依赖注入、runApp
│     │  ├─ app/                   # 应用壳
│     │  │  ├─ bootstrap.dart      # 启动流程：日志、存储、服务
│     │  │  ├─ router.dart         # 路由表
│     │  │  ├─ theme/              # 主题、字号、颜色
│     │  │  └─ platform/           # 平台差异入口（desktop / mobile / tv）
│     │  ├─ features/              # 按功能分：页面 + 控制器 + 组件
│     │  │  ├─ home/
│     │  │  ├─ live/               # 频道列表、EPG、换台浮层
│     │  │  ├─ vod/                # 分类、搜索、详情、选集
│     │  │  ├─ library/            # 本地与 NAS 浏览
│     │  │  ├─ player/             # 播放页、控制条、字幕音轨面板
│     │  │  ├─ cast/               # 设备列表、遥控
│     │  │  ├─ receiver/           # 接收端设置与状态
│     │  │  ├─ sources/            # 源管理、导入向导
│     │  │  └─ settings/
│     │  ├─ l10n/                  # 多语言 arb 文件
│     │  └─ shared/                # 通用组件、焦点导航、响应式布局
│     ├─ android/                  # 清单（含 leanback / TV 声明）、前台服务声明、network_security_config；applicationId：com.flytech.juying
│     ├─ windows/                  # runner、安装包与便携版打包脚本
│     ├─ assets/                   # 图标、默认预设清单（presets/）
│     ├─ integration_test/
│     ├─ test/
│     └─ pubspec.yaml
├─ packages/
│  ├─ core/                        # 纯 Dart：模型、错误码、Result、日志接口
│  ├─ storage/                     # drift 数据库、设置、安全存储封装、WebDAV 同步
│  ├─ net/                         # HttpClient、DNS / 代理 / 证书策略、编码检测
│  ├─ player_engine/               # PlayerEngine 抽象 + MpvEngine
│  ├─ source_providers/
│  │  ├─ m3u/                      # M3U、M3U8、TXT 直播源
│  │  ├─ cms/                      # CMS 接口
│  │  ├─ tvbox/                    # 配置解析与兼容层
│  │  ├─ spider_runtime/           # QuickJS 宿主与沙箱；jar 类站点的 Dart 移植放 tvbox/ports/
│  │  ├─ local_fs/ smb/ nfs/ webdav/ ftp/
│  │  └─ media_server/             # Jellyfin 等（P2）
│  ├─ epg/                         # XMLTV 流式解析、频道匹配、回看模板
│  ├─ proxy_server/                # 本地代理：透传、HLS 重写、文件 Range
│  ├─ discovery/                   # SSDP、mDNS 封装、网卡选择
│  ├─ cast_sender/                 # DLNA 发送端（后续 Chromecast / AirPlay）
│  ├─ receiver/
│  │  ├─ dlna_renderer/            # 设备描述、SOAP、GENA
│  │  └─ airplay_bridge/           # UxPlay 的 FFI / JNI 封装（实验）
│  └─ ui_kit/                      # Apple 风格设计令牌与组件、焦点感知、响应式与 TV 适配
├─ native/
│  ├─ android/                     # Kotlin：MulticastLock、前台服务、MediaSession
│  ├─ windows/                     # C++：SMTC、托盘辅助、防火墙引导
│  ├─ third_party/                 # UxPlay、libmpv 构建脚本与校验值
│  └─ rust/                        # （可选）协议核心工作区
├─ test_fixtures/
│  ├─ playlists/                   # M3U / TXT / EPG 样本
│  ├─ tvbox_configs/               # 兼容性样本
│  └─ dlna_captures/               # 各品牌电视的 SSDP / SOAP 抓包回放
├─ docs/
│  ├─ architecture/                # 本文拆分后的架构文档
│  ├─ adr/                         # 决策记录，一个决策一个文件
│  ├─ protocols/                   # DLNA / AirPlay / M3U / XMLTV 笔记
│  ├─ test-matrix.md
│  └─ release-checklist.md
├─ tools/                          # 脚本：构建 libmpv、抓包转夹具、生成图标
├─ .github/workflows/              # CI：分析、测试、构建、发布
├─ melos.yaml
├─ analysis_options.yaml
└─ README.md
```

### 6.2 目录与依赖规则

- **依赖方向**：core → net / storage → player_engine、source_providers、epg、discovery、proxy_server → cast_sender、receiver → apps。禁止反向依赖，packages 不得引用 apps。
- features 只依赖 packages 的抽象接口，不直接 import native/。
- 纯 Dart 包不依赖 Flutter，便于命令行单测与协议回放。
- 每个包自带 test/ 与 README，写明职责、公开 API 与已知限制。
- 平台差异集中在 platform/ 或用条件导入，不在业务代码里散落平台判断。

### 6.3 命名与代码约定

- 遵循官方 lints；文件名 snake_case；一个文件一个主要类型。
- 所有对外异常统一转成 AppFailure(code, message, cause)，错误码表放在 core/errors。
- 日志分级、带模块标签，脱敏过滤器统一放在 core。
- 提交信息前缀 feat / fix / refactor / docs / test / chore，并带需求编号，例如 feat(live): LIVE-05 线路自动切换。

## 7. 参考资料

### 7.1 开源项目对照（按模块）

> 以下来自 GitHub 公开检索，仅作参考；星标、活跃度和许可证请以仓库当前状态为准。GPL / AGPL 项目可参考，复用代码前先核对协议兼容性并保留署名。

| 模块 | 项目 | 值得参考的点 | 备注 |
| --- | --- | --- | --- |
| 整体形态 | nini22P/Iris | Flutter + media_kit 的 Windows / Android 播放器，WebDAV 接入、桌面快捷键 | AGPL-3.0；检索快照显示近一年更新较少 |
| 整体形态 | mangeshghodke/DreamPlayer | Flutter、Media3 与 libmpv 双引擎、SMB / WebDAV / FTP / Jellyfin / DLNA、Android TV 焦点 | GPLv3 |
| 播放内核 | media-kit/media-kit | 播放器库本体，以及 Android / Windows 的 libmpv 构建仓库 | 核对所带 libmpv 的许可证 |
| 播放内核 | mpv 手册（mpv.io） | 选项、硬解、网络缓存、字幕 | 官方文档 |
| 直播 | oerd/OwnTV | libmpv + ExoPlayer 双引擎分工、M3U / Xtream / Stalker、回看、遥控器交互 | Android TV |
| 直播 | 4gray/iptvnator | M3U、收藏、EPG、回看的数据模型 | TypeScript，跨平台 |
| 直播 | lizongying/my-tv | 国内直播软件的默认源、换台与操作习惯 | Android TV |
| 直播数据 | iptv-org/iptv、iptv-org/epg | 公开频道合集、频道数据库、EPG 工具与数据结构 | 测试数据与结构参考 |
| 直播数据 | fanmingming/live | 台标库 | 台标资源 |
| 线路择优 | Guovin/iptv-api | 源采集、筛选、测速、生成 | 测速与筛选逻辑 |
| TVBox | FongMi/TV | 多线路直播、自动换源、倍速、手机投屏；主流配置兼容基准 | Android |
| TVBox | q215613905/TVBoxOS、takagen99/Box | 其他常见分支，支持直播回放等 | Android |
| TVBox | catvod/CatVodOpen | 跨平台实现思路 | 以仓库说明为准 |
| TVBox | yagami-hue/Win-box | 把 TVBox 搬到 Windows 时的取舍（不含 jar 爬虫与 JVM 运行时） | Electron，个人项目 |
| TVBox 爬虫 | hjdhnx/dr_py、hjdhnx/drpy-node | dr 模板的 Python / Node 实现，JS 爬虫格式参考 | 仅参考格式 |
| NAS | XIONGPEILIN/mpvExtended-android（mpv NAS Player） | SMB / FTP / WebDAV、断线重连、可拖动代理 | Android |
| NAS | AlistGo/alist | 统一 WebDAV 出口 | AGPL-3.0；有文章提到项目归属近期变动，使用前核实 |
| DLNA 发送 | dart_cast | 纯 Dart 的 DLNA / AirPlay / Chromecast 发送，内置请求头代理，并列出已知限制 | pub.dev |
| DLNA 发送 | rusty_dlna | Rust 实现的发现与投放，Windows、Android 均支持 | pub.dev |
| DLNA 接收 | plutinosoft/Platinum | 跨平台 C++ UPnP 库，可做 DMR / DMS | 核对许可证 |
| DLNA 接收 | hzeller/gmrender-resurrect | 无界面 UPnP 渲染器，协议行为参考 | Linux / GStreamer |
| DLNA 旧库 | 4thline/cling | Java / Android 的 UPnP 栈 | 较老，据我所知已停止维护，仅作了解 |
| AirPlay | jqssun/android-airplay-server | 基于 UxPlay 的 Android 接收端：JNI 桥、MediaCodec 渲染、HLS 视频 | 首要参考 |
| AirPlay | FDH2/UxPlay | AirPlay 镜像与音频服务端核心 | GPLv3；新版可在 Windows 运行 |

注意一处矛盾：UxPlay 的 README 写明不支持 AirPlay 2 的视频流协议，而 android-airplay-server 声称支持 HLS 视频。到底是新版本已支持，还是它自己加了一层，需要在 M0 读代码并用真机测试确认。

### 7.2 规范与文档

| 主题 | 资料 | 用途 |
| --- | --- | --- |
| UPnP | UPnP Device Architecture（发现、描述、控制、事件）；UPnP AV 的 AVTransport、RenderingControl、ConnectionManager、ContentDirectory 服务模板（可在 Open Connectivity Foundation 的 UPnP 规范存档中查找，以官网为准） | DLNA 发送端与接收端的协议依据 |
| DLNA | 据我所知 DLNA 指南为会员文档，不公开；实践中以 UPnP AV 规范加各品牌设备抓包为准 | 兼容性处理 |
| HLS | RFC 8216（datatracker.ietf.org/doc/html/rfc8216） | 清单重写、直播分片 |
| HTTP Range | RFC 9110（datatracker.ietf.org/doc/html/rfc9110） | 代理的 Range / HEAD 行为 |
| XMLTV | wiki.xmltv.org | EPG 格式 |
| M3U 扩展 | iptv-org 仓库说明、Kodi IPTV Simple Client 文档 | tvg-* 属性、catchup 参数 |
| libmpv | mpv.io/manual/master | 播放选项与属性 |
| media_kit | github.com/media-kit/media-kit | 播放器库用法 |
| Android | Android 开发者文档：前台服务类型、WifiManager.MulticastLock、MediaSession、网络安全配置、画中画、TV 应用开发与质量要求 | 接收端保活、TV 适配 |
| Windows | Microsoft 文档：SMTC（System Media Transport Controls）、Windows 防火墙规则、MSIX 与安装器 | 系统集成与分发 |
| Flutter | 官方文档：桌面支持、平台通道、dart:ffi；flutter_rust_bridge 文档 | 原生集成 |
| AirPlay | 据我所知 Apple 不公开接收端规范；参考 UxPlay README 中列出的协议研究资料 | 逆向实现的背景 |

### 7.3 建议阅读顺序

1. Iris：理解 Flutter + media_kit 的工程骨架。
2. OwnTV、iptvnator：理解直播、EPG、回看、换线。
3. dart_cast、rusty_dlna：理解投屏发送端与请求头代理。
4. android-airplay-server + UxPlay：评估 AirPlay 接收端可行性，风险最高，越早验证越好。
5. Win-box、dr_py：评估 TVBox 在 Windows 上能做到什么程度。

## 8. 里程碑路线图

因采用 AI 辅助开发，右列周数只是按单人全职估算的旧参考值，实际节奏需重估；以验收标准作为完成依据。每个里程碑结束后回头修订第 9 章与第 11 章。

| 里程碑 | 目标 | 主要交付 | 验收标准 | 粗略量级（AI 辅助下需重估） |
| --- | --- | --- | --- | --- |
| M0 技术验证 | 把最大的不确定性变成结论 | PoC-1 media_kit 两端播放样本集（HLS、FLV、TS、HEVC）；PoC-2 SMB 大文件 Seek；PoC-3 向至少两台电视推 URL 并走代理；PoC-4 Android 前台服务承载接收端并保活 24 h；PoC-5 AirPlay 方案（android-airplay-server、Windows 上的 UxPlay），重点验证音频接收，镜像作为用户可开启的选项；PoC-6 QuickJS 跑通一个 TVBox JS 爬虫；PoC-7 NFS 客户端方案（Android、Windows）；PoC-8 Android TV 焦点导航、遥控器，以及 Apple 风格组件在 TV 与低端机上的性能；PoC-9 先统计所提供的配置与列表里 CMS、JS、jar 站点的数量，再选一个 jar 站点用 Dart 重写，验证可行性；PoC-10 4K、HDR、杜比（杜比音频如 AC-3、E-AC-3、Atmos 的直通，以及杜比视界）在 Media3 与 libmpv 上的对比，决定 TV 端默认引擎 | 每个 PoC 有结论记录，并更新 ADR 与风险表 | 1–2 周 |
| M1 骨架与播放闭环 | 可安装、可播放 | monorepo、CI、播放页、本地文件、M3U 导入与频道列表、基础设置、Apple 风格设计令牌、手机与 Android TV 双布局及焦点导航骨架 | 两端安装包可用；直播与本地文件可播（手机触控与 TV 遥控器均可操作）；解析层与协议层有单测 | 2–3 周 |
| M2 直播完整 | 日常可用的直播 | 分组、收藏、历史、多线路与自动换线、EPG、订阅更新、默认 CCTV 官方源（已接入，迁入新架构）、TV 遥控器换台与频道浮层 | 换台首帧达标；线路失败自动恢复；EPG 正确显示 | 2–3 周 |
| M3 NAS 与点播基础 | 能看 NAS | SMB、NFS、WebDAV（含 Alist）、外挂字幕、断点续播、断线重连 | 大文件拖动可用；断网后重连正常 | 2 周 |
| M4 投屏发送 | 推到电视 | 发现、推送、本地代理、设备画像、遥控 | 至少 3 台不同品牌电视可用；失败有降级与提示 | 2–3 周 |
| M5 DLNA 接收端 | 被手机推送 | 设备描述、动作与事件、前台服务与托盘常驻、防火墙引导 | 常见投屏 App 能发现并推送；两端常驻 7 天可用 | 3–4 周 |
| M6 TVBox | 兼容主流配置 | 配置导入、CMS、JS 爬虫、jar 类站点的 Dart 移植、能力矩阵与置灰提示 | 主流配置样本的导入成功率达到你设定的指标（建议先定义） | 3–4 周 |
| M7 AirPlay、同步与测试版 | 扩展与打磨 | AirPlay 音频（镜像为可选开关）、WebDAV 同步、TV 与低端机性能打磨、发布流程（安装包与便携版） | 24 h 长稳通过；发布 Beta | 4 周以上 |

## 9. 风险清单

| 编号 | 风险 | 影响 | 可能性 | 应对 |
| --- | --- | --- | --- | --- |
| R1 | AirPlay 实现不稳 | 高 | 高 | 后置；M0 先做 PoC；功能可整体裁剪 |
| R2 | jar 类爬虫的 Dart 移植工作量大、站点易失效 | 中 | 高 | 按站点清单逐个移植并配回归样本；能力矩阵与置灰提示 |
| R3 | DLNA 设备兼容性长尾 | 中 | 高 | 设备画像、抓包夹具、手动输入 IP 兜底 |
| R4 | Android 接收端被系统杀后台 | 高 | 高 | 前台服务、电池优化引导，必要时原生实现 |
| R5 | SMB 大文件 Seek 性能差 | 中 | 中 | M0 实测；备选 libsmb2 或代理 |
| R6 | libmpv 在低端盒子上性能或兼容不足 | 中 | 中 | 第二引擎 Media3；解码器设置 |
| R7 | 源频繁失效，体验差 | 高 | 高 | 多线路、测速、可远程更新预设 |
| R8 | 合规与下架风险 | 高 | 中 | 不内置内容；备选自行分发 |
| R9 | 依赖库维护停滞 | 中 | 中 | PlayerEngine 抽象；锁定版本；必要时自维护 fork |
| R10 | Windows 防火墙或多网卡导致找不到设备 | 中 | 高 | 网络诊断页、网卡选择、手动 IP |
| R11 | 开源许可证混用不兼容 | 高 | 中 | 项目许可证已定为 GPL-3.0；逐项核对依赖与复用代码的兼容性；维护第三方许可证清单 |
| R12 | 范围过大，难以完成 | 高 | 高 | 严格按里程碑推进；P2 不进 MVP |
| R13 | NFS 客户端在 Android、Windows 上缺少成熟方案 | 中 | 中 | PoC-7；备选系统挂载，或经 SMB / Alist 兜底 |
| R14 | 手机与 TV 同时首发，焦点与布局测试面扩大 | 中 | 高 | 先做 TV 骨架；用遥控器在真机与模拟器上持续回归 |
| R15 | 毛玻璃与动效在低端设备和 TV 盒子上掉帧 | 中 | 中 | 设计令牌里设性能预算；提供低性能模式 |
| R16 | AI 辅助开发引入协议细节错误（字段、动作名、响应头） | 中 | 高 | 协议实现以规范和抓包为准，用夹具回放与真机验证 |
| R17 | TV 首个版本要求 4K、HDR、杜比，libmpv 路线可能达不到（尤其杜比视界与音频直通） | 高 | 中 | PoC-10 对比 Media3 与 libmpv；Android TV 默认用 Media3，libmpv 作为兜底 |

## 10. 测试、构建与发布

### 10.1 测试分层

- **单元**：M3U / TXT / EPG 解析、频道归一化、线路评分、代理（Range、HLS 重写）、SOAP 编解码。
- **协议回放**：用抓包夹具回放各品牌电视的 SSDP / SOAP 交互。
- **集成**：integration_test 播放样本集（格式、编码、字幕、音轨）。
- **真机**：见 10.2。
- **长稳**：连续播放 24 小时；接收端常驻 7 天。
- **异常注入**：断网、丢包、DNS 失败、证书错误、源返回 403 或超时。

### 10.2 真机矩阵（建议最低覆盖）

| 类别 | 覆盖 | 关注点 |
| --- | --- | --- |
| 电视 / 投屏设备 | 至少 4 个不同品牌 | DLNA 兼容性、MKV / HEVC、字幕、Seek |
| Android 版本 | 9、11、13、14 及以上 | 前台服务、通知权限、存储访问、明文流量 |
| Android ROM | 原生 + 至少 2 个国产 ROM | 后台保活、自启动、电池优化 |
| Android 设备 | 旗舰、中端、低端盒子（armeabi-v7a） | 解码能力、内存、性能 |
| Windows | 10 与 11；单网卡与多网卡；有无 Bonjour；安装版与便携版 | 防火墙、SSDP / mDNS、SMTC |
| Android TV / 盒子 | 至少 2 款（含 1 款支持 4K、HDR、杜比的设备，以及 1 款低端 armeabi-v7a 盒子） | 焦点导航、遥控器键位、解码能力、毛玻璃性能 |

### 10.3 构建与 CI/CD

- **PR**：格式与静态分析、单元测试、协议回放测试。
- **Tag**：构建 Windows（便携 zip + 安装包）与 Android（按 ABI 拆分 APK），产物签名，生成发布说明与更新检查 JSON。
- **原生依赖**（libmpv、UxPlay）用脚本从固定版本构建，记录来源与校验值。

### 10.4 发布检查清单

- 第三方许可证清单与致谢页；原生库版本与校验值。
- 隐私政策与免责声明；应用内不含任何第三方内容。
- 代码签名；Windows 病毒误报自查。
- 升级与回滚验证；配置迁移测试。
- 日志导出可用；FAQ 已写（尤其是“找不到设备”）。

## 11. 已确认决定与待决问题

| 编号 | 问题 | 已确认的决定 | 对本文的影响 |
| --- | --- | --- | --- |
| Q1 | Android TV 是否是正式目标？ | 是，手机与 TV 同为正式目标，首个版本就要 | TV 焦点导航升为 P0；TV 骨架并入 M1；见 5.11 |
| Q2 | AirPlay 做到什么程度？ | 默认音频，镜像由用户手动开启 | APL-01、APL-02 升为 P1，镜像保持 P2 且默认关闭；5.8 的安全策略已调整 |
| Q3 | 能否接受 Windows 不支持 jar 类爬虫？ | 希望用 Dart 实现 jar 类爬虫 | 改为 Dart 重新实现（Dart 不能直接执行 jar），见 5.9、ADR-008 |
| Q4 | 开源还是闭源？ | 开源，自用，支持公开发布 | GPL 组件可集成；许可证建议见 11.1 |
| Q5 | 默认 CCTV 源方案？ | 使用官方公开网址，已接入 | LIVE-02 已更新；M2 改为迁入新架构 |
| Q6 | NAS 协议？ | Samba、NFS 为主，暂先接入 Alist | NFS 升为 P1 ⚠️（需 PoC-7）；FTP / SFTP 降为 P2 |
| Q7 | 开发人数与时间预算？ | 直接用 AI 辅助开发 | 周数估算作废；新增 12.5 AI 辅助开发约定 |
| Q8 | 账号或同步？ | 用户自行配置 WebDAV 同步 | 新增 APP-12；仍不做自有账号与云服务 |
| Q9 | Windows 分发形态？ | 安装包与便携版都要 | 见 3.3、10.3 |
| Q10 | Android 最低版本？ | Android 9 | minSdk 28；测试矩阵已调整 |
| Q11 | UI 风格？ | 参考苹果风格 | 新增 5.11（含字体与图标的许可注意） |

### 11.1 许可证（已确认 GPL-3.0）

已确认采用 GPL-3.0（是否加 or-later 可在发布前再定）：这样可以直接集成 UxPlay（GPLv3），也能在保留署名的前提下复用多数 GPL 参考项目。若想复用 AGPL-3.0 的代码（如 Iris），据我所知 GPLv3 允许与 AGPLv3 组合，但组合后的网络服务条款仍然适用，这时 AGPL 部分的网络服务条款仍需遵守，复用前请逐个核对。GPL 与 Apple App Store 的条款存在已知冲突，但你不做 iOS，影响不大；各安卓商店对开源应用的政策以其当前规则为准。以上不是法律意见，发布前请自行核对或咨询专业人士。

### 11.2 新产生的问题与回答

| 编号 | 问题 | 你的回答与影响 |
| --- | --- | --- |
| N1 | 项目许可证：已确认 GPL-3.0（复用 AGPL 代码前需单独核对兼容性） | 已确认，不再待决 |
| N2 | 你实际要兼容的 TVBox 配置和 jar 站点清单是什么？ | 已提供四个聚合配置源或列表作为兼容性样本：25175 聚合源（GitHub：tvyuan）、Jinenge 聚合配置（GitHub：tvbox）、饭太硬接口源、juwanhezi 的 TVBox 源列表（jsonlist）。这类配置里的站点授权情况不一，应用只提供格式兼容，不内置、不推荐具体站点；具体地址保存在本地测试夹具，不进入公开仓库。M0 先统计其中 CMS、JS、jar 站点的数量（PoC-9）。 |
| N3 | NFS 在 Windows 与 Android 上各用什么方案，能否先接受“经 SMB 或 Alist 兜底”？ | 此前用类似 mount 的方式测试过（我按系统挂载理解，具体做法待你补充）；仍按 PoC-7 分别验证 Windows 与 Android，结论分开记录。 |
| N4 | TV 首个版本要支持哪些设备？是否要求 4K、HDR、杜比直通？ | 需要 4K、HDR、杜比（已确认杜比音频与杜比视界都要）。已把 PLY-13 升为 TV 首个版本必备，并引入 Media3 作为 Android TV 的第二引擎（见 5.3、ADR-002、R17）；杜比音频直通与杜比视界需分别验证（PoC-10）。 |
| N5 | AirPlay 音频默认开启时，对局域网内所有设备可见，还是需要 PIN 或白名单？ | 默认局域网内可见，不强制 PIN；白名单与 PIN 作为可选项，并保留一键关闭。 |
| N6 | WebDAV 同步范围：源配置、收藏、历史、设置各自是否同步？凭据是否同步（加密）？ | 源配置、收藏、历史、设置都可同步；凭据按加密后同步来设计（APP-12），如不同意请告知。 |
| N7 | Apple 风格的落地深度：全量自绘，还是尽量复用 Cupertino 组件？ | 尽量使用 Cupertino 组件；ui_kit 只做设计令牌与必要封装，TV 焦点卡片、毛玻璃控制条等无法现成使用的部分再自建（见 5.11、ADR-010）。 |
| N8 | 应用名称与图标是否已定？ | 名称定为“聚映”，Android 应用 ID 为 com.flytech.juying。上架前仍建议在应用商店与商标库查重。 |

## 12. 附录

### 12.1 源配置示例（示意）

```yaml
schema_version: 1
sources:
  - id: preset-cctv
    type: m3u
    name: CCTV（预设，可删除）
    url: <官方公开网址>
    headers: { user-agent: 'Mozilla/5.0' }
    enabled: true
  - id: nas-home
    type: smb
    name: 家里的 NAS
    host: 192.168.1.10
    share: video
    credential_ref: cred-nas-home   # 凭据放安全存储，这里只存引用
    enabled: true
```

### 12.2 设备画像示例（示意）

```yaml
id: example-tv
match: { manufacturer: ExampleCorp, model_regex: '^EX-.*' }
quirks:
  supports_range: true
  supports_mkv: false            # 需要转封装
  supports_hevc: true
  requires_content_features: true
  ignore_sidecar_subtitle: true
```

### 12.3 术语表

| 术语 | 含义 |
| --- | --- |
| SSDP | 简单服务发现协议，UPnP 设备通过组播互相发现 |
| UPnP / DLNA | 通用即插即用 / 基于 UPnP AV 的家庭媒体互联规范 |
| DMR / DMS / DMC | 数字媒体渲染器 / 服务器 / 控制器 |
| GENA | UPnP 的事件订阅机制 |
| DIDL-Lite | UPnP AV 中描述媒体条目的 XML 格式 |
| AVTransport | UPnP 的播放控制服务 |
| EPG / XMLTV | 电子节目单 / 其常用的 XML 格式 |
| M3U / M3U8 | 播放列表格式 |
| HLS | HTTP Live Streaming，基于 HTTP 的分片流媒体协议 |
| SMTC | Windows 系统媒体传输控件 |
| MulticastLock | Android 上允许接收组播包的锁 |
| ABI | Android 上指 CPU 架构 |
| PoC | 概念验证 |
| ADR | 架构决策记录 |

### 12.4 第一周行动清单

- [ ] 建仓库，配置 melos、fvm 与 CI 空壳
- [ ] 在 Windows 与一台 Android 真机跑通 media_kit 示例
- [ ] 整理样本集：各类 M3U / TXT / EPG，以及不同编码与容器的视频
- [ ] 准备 2–3 台不同品牌的电视，用 Wireshark 抓一次手机投屏
- [ ] 开始 PoC-1 至 PoC-3
- [ ] 确认 11.2 中的新问题（至少 N2–N4）

### 12.5 AI 辅助开发约定

- **项目说明文件**：仓库根放一份给 AI 的说明（如 AGENTS.md 或 CLAUDE.md），写明技术栈、目录与依赖规则、命名与错误码、禁止事项（例如不在 features 里写协议代码）。
- **上下文要小**：本文拆分后放进 docs/，每次任务只给 AI 相关章节和对应需求编号，不要把整份文档塞进上下文。
- **任务粒度**：一个需求编号一个任务；先让 AI 写测试或夹具，再写实现；每个任务附验收标准（第 2、8 章）。
- **协议代码不能只信 AI**：DLNA、AirPlay、HLS 重写、SMB / NFS 必须用抓包夹具或真机验证；AI 容易编造字段、动作名和响应头，一律以规范和抓包为准。
- **依赖要核对**：AI 引用的包名、版本、方法，先到 pub.dev 或官方仓库核对，再锁定版本。
- **jar 站点移植**：把原站点的请求与解析规则逐个分析后交给 AI 生成 Dart 实现，配样本回归测试，每个站点单独提交。
- **评审**：AI 的改动仍走 PR 与 CI；人工重点看安全（代理、接收端）、许可证（引入代码的来源与协议）、资源释放（isolate、socket、播放器实例）。
- **许可证卫生**：让 AI 参考开源项目时，要求它标明借鉴来源，不要大段照搬 GPL / AGPL 代码而不标注。
- **小步提交、频繁真机验证**：M0 的 PoC 结论记录作为后续任务的事实来源。
