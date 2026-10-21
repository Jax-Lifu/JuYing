# 聚映 (JuYing) 项目工程约束与指导原则

> 权威基准：以 **[《聚映项目指导文档 v0.2》](docs/PROJECT_GUIDE.md)** 与 **[11大架构决策 (docs/adr/)](docs/adr/)** 为最高准则。

## 1. 核心工程原则
- **目标平台定位**：主线目标平台为 **Windows 10/11** 与 **Android 9+ (minSdk 28，手机/平板/Android TV 首发同时支持，ADR-011)**；applicationId: `com.flytech.juying`。所有平台共用统一的领域模型、业务契约与底层抽象，杜绝碎片化重复实现。
- **开源许可证规范 (ADR-009)**：项目采用 **GPL-3.0** 许可证。代码复用必须遵守开源卫生要求，保留原作者署名与版权声明；第三方原生库（libmpv、UxPlay）固定版本与校验值。
- **内容解耦原则 (ADR-005)**：应用自身**严禁内置、分发或运营任何第三方媒体源**；默认源仅为用户可查看、可编辑、可删除的示例预设。
- **协议与 UI 分离 (ADR-007)**：协议解析、网络请求改写、SOAP 报文必须能脱离 Flutter 界面框架单独在纯 Dart 命令行与测试环境中运行。
- **提交信息与需求编号规范**：提交信息前缀必须采用 `feat / fix / refactor / docs / test / chore`，并强制关联需求编号，例如：`feat(live): LIVE-05 线路自动切换`、`fix(cast): CAST-02 进度同步异常`。
- **敏捷调试与进程处理**：编译调试时若遇到已有 Windows 进程占用，直接终止（kill）被占用的进程并重新构建。执行命令与修改时默认同意执行，保持敏捷高效。

## Grill Mode（需求拷问模式）
- 当用户明确说出 `grill me` 时，不得立即开始实现。
- 以积极且建设性的方式严格挑战现有假设。
- 识别含糊、不完整或相互冲突的需求。
- 质疑架构与技术选型，并要求说明其必要性与取舍。
- 主动检查边界情况、故障模式及恢复策略。
- 识别并削减不必要的复杂度。
- 每次只提出一个影响最大的关键问题，等待用户回答后再继续追问。
- 持续追问，直到主要不确定性均已消除。
- 最后输出完整、可执行的实施计划。

## 2. 架构与技能规范
- 必须严格遵循 `.agents/rules/juying-architecture-constraints.md` 中定义的架构规范与 11 大 ADR（[ADR-001 ~ ADR-011](docs/adr/)）。
- 针对各核心子系统，参考并遵循 `.agents/skills/` 下的 10 大领域技能：
  - `video-player-core`: 播放内核（media_kit / libmpv 通用内核 + Android TV 4K/HDR/杜比 Media3 第二引擎，ADR-002）、硬解故障平滑降级、多音轨/字幕延迟微调、弹幕渲染引擎与 D-Pad 交互。
  - `iptv-live-engine`: IPTV M3U/TXT/JSON 格式、CCTV 动态流、IPv4/IPv6 探测与 2 秒快速切台（LIVE-08）、EPG 与时移回看。
  - `tvbox-spider-sandbox`: QuickJS 沙箱、TVBox 单仓/多仓/加密配置、CatVod 爬虫协议、Jar 站点 Dart 移植规范（`tvbox/ports/`，ADR-008）、统一实体/候选分离、搜索防抖。
  - `lan-nas-streaming`: Samba/NFS/WebDAV 协议（LIB-07 NFS P1）、本地回环 `127.0.0.1:9978` Range 代理与手机局域网远程配置门户。
  - `cloud-drive-engine`: 网盘流通过 WebDAV / Alist 虚拟挂载桥接（LIB-03 / ADR-005），Token 硬件存储与 302 重定向。
  - `media-metadata-scraper`: TMDB/豆瓣/Bangumi 元数据抓取、详情并行预取与 Generation Token 守卫、脏标题正则清洗。
  - `dlna-cast-engine`: DLNA/UPnP 双角色架构（DMC 手机/PC 发送端与 DMR 大屏/TV 接收端）、SSDP 发现与回环代理桥接。
  - `sync-storage-engine`: WebDAV 多端双向数据同步（APP-12：源配置、历史、收藏、设置；凭据加密同步，LWW 冲突合并与备份）。
  - `offline-download-manager`: M3U8 多线程切片并行下载、AES-128 在线解密、MP4 自动无损重封装与后台断点续传（P2）。
  - `webview-sniffer-engine`: 无头 WebView 流量拦截嗅探（`.m3u8`/`.mp4`）、Cloudflare 验证码弹窗穿透与 Cookie 捕获。
- **UI 风格与视觉规范 (ADR-010)**：
  - 参考 Apple 设计风格，以 Cupertino 组件为基底，集中收口 `ui_kit` 设计令牌。
  - 默认深色模式（Cinema Dark），采用开源字体 Inter/系统字体与开源图标库（Lucide/Phosphor）。
  - 强制提供**低性能模式 (Low Performance Mode)**：在低端设备上将高开销毛玻璃实时模糊降级为纯色半透明，确保 60fps 流畅。

## 3. 代码注释规范 (工程师思维)
- **默认编写注释**：所有公开 API、核心实体、跨线程/异步协调、协议转换与异常回退逻辑必须默认编写注释。
- **只写“为什么 (Why)”与“做什么 (What)”**：
  - **What (做什么)**：精确概括方法/类对外的契约职责、假设前提与返回保证。
  - **Why (为什么)**：核心聚焦设计动机、架构权衡（Trade-off）、规避特定平台 Bug 或协议陷阱的深层原因。
- **严禁 AI 思维的无意义复读**：杜绝机械翻译代码语法的行级废话（如 `// i 递增`、`// 返回数据`、`// 这是一个用于初始化的方法`）。代码本身展现“How”，注释必须注入高密度的工程思考与设计上下文。

## 4. 代码格式化与代码风格规范 (Format by Default)
- **默认格式化**：所有新增与修改的代码文件必须严格遵循相应语言的官方 Format 与 Lint 规范，严禁提交格式混乱的代码。
- **Dart / Flutter 规范**：
  - 严格遵循 `dart format` 与 Effective Dart 规范，保持统一排版。
  - Widget 树与多参数列表必须合理利用尾随逗号（trailing comma `,`），确保格式化后呈现结构清晰的声明式视图树。
  - 严禁无序 import，按 `dart:*`、`package:*`（第三方库）、`package:juying/*`（本工程内部）、相对路径顺序组织导入。
- **其他语言规范（脚本/插件/子模块）**：
  - Kotlin: 遵循 `ktlint` / Android Kotlin Style（4 空格缩进，禁止通配符 import）。
  - Go: 严格遵循 `gofmt` / `goimports`。
  - TypeScript / JS / JSON: 统一遵循 2 空格缩进与 Prettier 风格。
  - Python: 严格遵循 `ruff` / `black` / PEP 8。
- **文件与排版洁癖**：统一使用 UTF-8 编码与 LF 换行符，文件末尾保留单个空行，严禁行尾多余空白字符（trailing whitespace）。
