# 聚映 (JuYing) 核心架构与工程约束规范

> 权威基准：以 **[《聚映项目指导文档 v0.2》](docs/PROJECT_GUIDE.md)** 与 **[11大架构决策 (docs/adr/)](docs/adr/)** 为最高技术约束。

## 1. 领域模型与数据隔离原则 (Animeko & Kazumi Pattern)
- **实体身份与播放候选解耦**：全局媒体模型严格划分为规范实体 `MediaItem`（由 TMDB / Douban / Bangumi 唯一主键驱动）与具体源候选 `PlaybackCandidate`（关联站源、线路名称、画质、音频与请求头），严禁站源私有字段污染核心实体。
- **搜索请求 Epoch 机制**：全局跨源并发检索必须使用防抖（Debounce 300ms）与单调递增 `searchEpochId` / `CancelToken`。旧请求的响应严禁覆盖新搜索结果。
- **元数据并行预取与 Generation Guard (WebHomeTV2 Pattern)**：进入详情页时，条目的 TMDB 核心元数据请求与爬虫 `detailContent()` 并发执行。页面切换时必须推进 `loadGeneration`，防止跨条目数据竞态污染。
- **运行时会话统一抽象 (ADR-007)**：无论是本地点击、DLNA 投送还是 AirPlay 接收，统一封装为不可变 `PlaybackSession` 运行时会话交由统一播放内核调度。

## 2. 播放内核与双引擎分工原则 (ADR-002: FongMi / OwnTV / DreamPlayer Pattern)
- **通用内核与 Android TV 双引擎**：
  - Windows、Android 手机端及通用场景默认使用 `media_kit` (libmpv 底层) 驱动 `MpvEngine`，确保流媒体解码跨端行为一致。
  - Android TV 大屏引入 Android 原生 `Media3` (ExoPlayer) 作为第二引擎 (`Media3Engine`)，专注承载 **4K、HDR、杜比音频直通 (AC-3 / E-AC-3 / Atmos) 与杜比视界 (Dolby Vision)** 硬件特性（PLY-13 / PoC-10）。
- **硬解故障自愈与平滑降级 (PLY-02)**：默认开启硬件加速（Windows: `d3d11va`, Android: `mediacodec`）。若纹理创建失败或出现解码异常，必须自动捕获并无感回退至软件解码（`hwdec: no`），严禁黑屏或崩溃。
- **音频/字幕时序校准与弹幕层 (PLY-04)**：
  - 提供毫秒级音轨延迟微调（`±50ms`）与字幕延迟微调（`±100ms`）。
  - 顶层叠加全格式透明弹幕渲染引擎（支持 Bilibili XML、DPlayer JSON 格式），具备智能分道防重叠与关键词过滤。

## 3. 网络与 IPTV / CCTV 协议解析原则 (Guovin / iptv-org Pattern)
- **IPv4 / IPv6 双栈探测 (LIVE-01/05)**：应用启动时异步探测本地网络环境，智能提升可达协议（如 IPv6 专属 4K/8K 直播源）的优先级；对无 IPv6 环境自动规避 IPv6 节点以消除长等待超时。
- **CCTV 官方直播与片库点播 (tv.cctv.com/yxg, LIVE-02)**：
  - 严禁硬编码临时 CDN 视频地址。直播与点播统一调用 CNTV / VDN 接口动态换取带安全鉴权 Token 的 1080P/4K HLS 清单。
  - 完整支持央视片库专辑检索与栏目大全分集解析；默认预设用户可完全编辑与删除（ADR-005）。
- **请求头动态注入 (PLY-07)**：严格支持 `#EXTVLCOPT`、`#EXTHTTP` 及 URL 查询后缀规则（`User-Agent`、`Referer`、`Origin`、`Cookie`）。
- **2秒快速换台与故障无感换源 (LIVE-05/08)**：首帧起播目标 ≤ 2s；直播流卡顿 >3000ms 或遭遇 403/404/500 HTTP 报错时，触发熔断器自动切换到最优健康线路并持久化线路评分。
- **EPG 频道匹配级联规则 (LIVE-06)**：匹配优先级严格遵循：`tvg-id` 优先 -> 频道别名表 -> 规范化名称（去符号空格/数字归一） -> 模糊匹配。

## 4. 本地代理与安全边界原则 (ADR-006: Local Range Proxy)
- **微型代理统一出口 (`127.0.0.1:9978`)**：Samba (SMBv2/v3)、WebDAV（含 Alist 挂载）及需注入特殊防盗链请求头的流媒体，统一通过本地微型 HTTP 代理转换为标准 `206 Partial Content` Range 分块流。
- **严密安全边界与防 SSRF**：
  - 代理服务仅绑定局域网网卡或本地回环 `127.0.0.1`，严禁向公网开放；
  - 代理 URL 使用高熵一次性短期有效 Token (UUID v4)；
  - 强制执行目标地址白名单过滤，禁止代理访问内部回环敏感端口与内网路由管理页面，杜绝 SSRF 漏洞。
- **安全凭据存储**：NAS 账号密码与 WebDAV 凭据仅存入平台硬件级加密存储（`flutter_secure_storage`），禁止明文日志与明文持久化。

## 5. TV 遥控器与跨屏互联原则 (PickTV / FongMi Pattern)
- **TV Focus First (APP-04 / ADR-011)**：大屏页面所有可交互元素必须具备明确的 `FocusNode`，焦点必须具备高对比度发光外框与呼吸缩放动效。
- **DLNA 双角色架构 (ADR-003: CAST & DMR)**：
  - 移动端/PC 作为 DMC 投屏发射端：支持 SSDP 组播发现与手动输入 IP 兜底，支持 Play / Pause / Seek / 音量调节全量控制。
  - 大屏/桌面端注册为标准 DMR 接收端：响应 AVTransport / RenderingControl，安全上仅接受 `http/https`（拒绝 `file://` 等私有 scheme），支持来源白名单与配对 PIN。
- **设备兼容性画像 (DeviceProfile, CAST-04)**：针对不同电视品牌（小米、华为、索尼、三星等）维护设备特征画像（`supports_range`, `supports_mkv`, `supports_hevc`, `requires_content_features`），根据画像动态降级转封装或改写 MIME。
- **AirPlay 接收端策略 (APL-01~05 / ADR-004)**：音频接收默认开启（局域网可见），屏幕镜像默认关闭（用户按需开启），支持 PIN 与访问控制。

## 6. TVBox 兼容层与沙箱原则 (ADR-008: Spider Sandbox & Ports)
- **CMS 接口原生支持 (VOD-03)**：全平台原生 HTTP 高效解析。
- **QuickJS 爬虫沙箱严格受控 (VOD-04)**：
  - 沙箱内部严禁注入 `dart:io`、文件系统、环境变量与系统进程通道；
  - 爬虫发起的 HTTP 请求受限重定向至宿主受控客户端，强制设置 **6 秒硬超时** 与 **32MB 内存硬上限**；
  - 页面销毁或切源时显式释放 JS 虚拟机堆栈，严禁内存泄漏。
- **Jar 站点 Dart 移植规范 (VOD-07 / ADR-008)**：
  - 常用 Jar 站点采用 Dart 重新实现，存放在 `packages/source_providers/lib/tvbox/ports/`；
  - 抽取共用规则沉淀为解析规则引擎；Android 保留原生加载 DEX 兜底（默认关闭）。
- **平台能力感知与置灰 (VOD-06)**：遇到当前平台未移植且不支持的站点类型，在 UI 显式置灰并提示原因，严禁静默失败。

## 7. UI 与设计语言规范 (ADR-010: Apple Style & Low Performance Mode)
- **Apple 风格设计系统**：
  - 统一设计令牌：集中在 `ui_kit`，涵盖留白比例、大标题层级、圆角标尺、模糊强度与柔和动效曲线。
  - 优先复用 Flutter Cupertino 基础组件（大标题导航栏、分组列表、分段控件、弹层与操作表），自建 TV 焦点外发光卡片与毛玻璃播放器控制条。
  - 默认深色模式（Cinema Dark）；使用系统字体或开源字体（Inter），图标使用开源库（Lucide / Phosphor），严禁违规分发 Apple SF 字体与图标资源。
- **自适应低性能模式 (APP-13 / R15)**：
  - 针对低端 Android 盒子与老旧电视芯片，提供低性能模式；
  - 自动将实时背景模糊（BackdropFilter）降级为不透明度纯色半透明背景，停用复杂动态呼吸光效，确保客厅 60fps 流畅交互。

## 8. 开源许可与代码卫生规范 (ADR-009: GPL-3.0)
- **项目主协议**：全仓库采用 **GPL-3.0** 许可证发布。
- **代码复用与致谢**：参考或复用第三方开源项目（如 UxPlay、DreamPlayer、Iris 等）时，必须严格遵守协议规范，完整保留原作者署名与版权头信息。
- **原生依赖追溯**：libmpv、UxPlay 等预编译库必须固定版本号，并在发布清单中附带 SHA-256 校验值。

## 9. 工程师级代码注释规范 (Engineering-Grade Comments)
- **默认编写注释**：公开契约、复杂算法、协议桥接、状态转换与并发保护等核心代码必须默认配备清晰注释。
- **严格遵循“Why + What”原则**：
  - **What (做什么)**：简明阐明模块/函数对外的业务契约与技术承诺，指明入参假设与边界表现。
  - **Why (为什么)**：核心阐明架构设计背后的工程动机、技术选型权衡（为何不采用直觉方案）、规避特定平台缺陷/协议坑点的依据。
- **杜绝 AI 式机械复读**：
  - 严禁对显而易见的语法做逐行直译（如 `// 将列表长度赋值给count`、`// 创建一个播放器对象` 等低信息密度噪音）。
  - 代码负责展现“How”，注释必须注入高价值的“Context”、“Trade-offs”与“Constraints”。

## 10. 代码格式化与静态检查规范 (Code Formatting & Static Analysis)
- **默认执行代码格式化**：所有写入或变更的代码必须默认符合官方 linter 与 formatter 规则（`dart format`）。
- **声明式 UI 尾随逗号原则**：Flutter 组件树嵌套必须规范使用尾随逗号（trailing comma `,`），促使 formatter 展开多行清晰缩进。
- **导入语句（Imports）拓扑有序**：系统库 -> 第三方依赖 -> 项目内部包 -> 相对路径，禁止无用未消费 import 与通配符导入。
- **文件整洁度**：统一 UTF-8 编码，统一 LF 换行符，清除行尾多余空白字符（trailing whitespace），文件末尾保留单换行符。
