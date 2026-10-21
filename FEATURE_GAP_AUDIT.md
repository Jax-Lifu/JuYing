# JuYing 功能缺口回归审计

审计日期：2026-08-22  
审计基线：`analysis/README.md`、`.agents/rules/juying-architecture-constraints.md`、10 个领域技能规范、当前 `lib/` 与 `test/`。

## 1. 判定口径

- **已实现**：存在真实协议或数据链路，已接入 UI/业务流程，并有覆盖关键行为的测试或可复现验证。
- **部分实现**：主链路可用，但缺少规范中的重要分支、平台能力或可靠性保证。
- **骨架/模拟**：存在类、页面或返回模型，但关键结果由固定数据、示例 URL 或延时模拟产生。
- **缺失**：没有可执行实现或没有任何调用入口。

README 中的功能声明不能单独作为完成证据；类名、注释和通过 mock 数据的测试也不能证明真实协议可用。

## 2. 总体结论

| 子系统 | 当前状态 | 结论 |
| --- | --- | --- |
| CCTV 官方片库与动态 HLS | 已实现/部分实现 | 官方列表、分集、GUID 动态解析、清晰度变体已有真实接口与测试；直播仍有 Web 官网播放器旁路，尚未完全统一到 `media_kit`。 |
| LAN NAS 与 Range 代理 | 部分实现（完成度高） | SMBv2、NFSv3、WebDAV 浏览和 Range 桥接已有真实实现；NFSv4、代理边界校验、远程门户完整配置能力仍缺。 |
| 播放内核与弹幕 | 部分实现 | `media_kit`、基础硬解回退、3 秒看门狗、比例、延迟调节、历史和 XML/JSON 弹幕已接入；硬解无感恢复、轨道选择、外挂字幕、弹幕过滤/固定弹幕仍不完整。 |
| IPTV 直播 | 部分实现 | M3U/TXT、请求头、缓存、IPv6 探测、线路健康探测和播放器换线已有实现；TVBox Live JSON、XMLTV、回看插值、吞吐采样和完整错误熔断缺失。 |
| TVBox / CatVod | 骨架/模拟 | 配置宽松 JSON 和部分 CBC 解密可用；非 CCTV 的分类、搜索、详情和播放线路仍由固定 mock 数据及固定 CCTV GUID 生成，没有 QuickJS/CatVod 运行时。 |
| 云盘 | 骨架/模拟 | Token 可写入安全存储，但刷新和直链均为模拟；没有任何 UI/业务调用，也没有真实供应商 API、聚合搜索、302/转码或 Alist 挂载。 |
| 元数据刮削 | 骨架/模拟 | 标题清洗和 generation guard 形式存在；TMDB/豆瓣/Bangumi 请求、缓存、季集映射均不存在，服务也没有业务调用。 |
| DLNA | 部分实现 | DMC 的 SSDP 发现、`SetAVTransportURI`、`Play` 可用；暂停、停止、Seek、音量、DIDL 元数据、受保护流代理和 DMR 接收端缺失。 |
| WebDAV 同步 | 部分实现 | Gzip 上传下载和历史 LWW 已实现；路径契约、分文件同步、收藏合并、字段级冲突、删除墓碑、ETag、原子 MOVE、凭据安全存储和自动触发缺失。 |
| 离线下载 | 骨架/高风险 | 能并发下载并拼接未加密 TS；没有 Master Playlist 选择、AES-128、失败重试、完整性校验、FFmpeg remux、断点持久化、直链 Range、空间检查和移动端后台任务。当前把 TS 字节直接命名为 `.mp4`。 |
| WebView 嗅探 | 缺失 | `lib/` 中没有嗅探服务、请求拦截、媒体匹配、Cookie 获取或 Cloudflare 交互升级实现。 |
| 主题与 i18n | 部分实现 | 有主题 Token 和 i18n 服务，但大量页面文案及 `Colors.*` 仍硬编码，尚未达到“文案全量字典化、颜色全量 Token 化”。 |

## 3. 逐项证据与缺口

### P0：当前实现会产生错误功能预期

1. **TVBox 非 CCTV 内容仍是假数据**
   - `tvbox_spider_engine.dart` 的分类回退调用 `_buildSiteMockMedia`。
   - 聚合搜索对每个站点同样读取 mock 列表；无结果时还会生成一个伪搜索结果。
   - 播放详情为所有站点生成固定 CCTV GUID，而不是调用 CatVod `detail/play`。
   - 需要实现 QuickJS 隔离执行器、CatVod 完整方法契约、超时/内存/网络边界，以及 MacCMS 详情与播放解析；完成前 UI 应明确标记演示源，不能宣称已接入饭太硬/肥猫/巧儿。

2. **云盘直链和 Token 刷新是模拟实现**
   - `cloud_drive_service.dart` 返回 `drive.stream.example.com`，刷新 Token 通过时间戳拼接生成。
   - `CloudDriveService` 在 `lib/` 中没有调用方。
   - 需要按供应商拆分 adapter，先落地统一认证/刷新/直链结果契约，再逐个接入阿里、夸克、115、百度、123/UC；所有短效 URL 必须接入本地代理。

3. **元数据返回是模拟结果**
   - `media_metadata_service.dart` 仅延迟 150ms 后返回固定评分和类型。
   - 服务只被标题清洗测试引用，没有详情页调用。
   - 需要接入 TMDB、豆瓣、Bangumi provider，建立 L1/L2 缓存、季集映射，并让详情页并行执行 spider detail 与 metadata enrichment。

4. **离线 `.mp4` 不是合法重封装**
   - 下载器跳过全部 `#` 指令，未解析 `#EXT-X-STREAM-INF` 和 `#EXT-X-KEY`。
   - 分片失败只打印日志，仍继续拼接并把 TS 字节写入 `.mp4` 文件名。
   - 必须在任何“离线下载完成”状态前增加分片完整性校验；AES-128 解密和 FFmpeg `-c copy` 重封装是完成条件。

### P1：主链路存在，但未达到分析规格

1. **IPTV / EPG / 回看**
   - 已解析 `catchup-source` 到模型，但没有 XMLTV 读取、频道模糊匹配和回看 URL 插值方法。
   - Live 页面展示的是内置示例 `EpgProgram`，不是 EPG 源数据。
   - 没有 TVBox `lives` JSON 解析；线路探测主要验证可访问性，没有按最后两个分片采样首包与吞吐。

2. **播放器**
   - 硬解失败时对任意 `open` 异常统一切软件解码，可能把 403、DNS 和清单错误误判为解码错误。
   - 回退没有保留当前播放位置，也没有纹理/丢帧监测；软件回退状态会跨后续媒体保持。
   - OSD 有音频/字幕延迟和比例控制，但没有真实音轨、字幕轨选择和外挂字幕加载 UI。
   - 弹幕支持 Bilibili XML、DPlayer JSON 和滚动轨道；缺少顶部/底部固定弹幕、关键词/正则过滤、显示区域与速度配置。

3. **DLNA**
   - 只发现 AVTransport 服务，没有保存 RenderingControl 控制地址。
   - 只实现投送和播放，缺少 Pause/Stop/Seek/SetVolume/GetPositionInfo。
   - `CurrentURI` 直接插入 XML，未做 XML 转义；`CurrentURIMetaData` 为空。
   - 没有 SSDP advertiser、设备描述、SCPD、事件订阅和接收播放桥接，因此 DMR 完全缺失。

4. **WebDAV 同步**
   - 当前远端文件是单一 `juying_sync.gz`，不符合 `/JuYing/sync/v1/*.json.gz` 契约。
   - 合并仅完整处理 history；favorites 直接取本地，settings 直接取本地，subscriptions 只按 bundle 总时间二选一。
   - 没有 `entityId/updatedAt/isDeleted` 统一实体、ETag 并发保护、临时文件 + MOVE 原子写入、dirty tracking 和启动/播放退出触发器。
   - 设置页直接传用户名密码给服务，WebDAV 凭据没有独立安全存储层。

5. **NAS / 本地代理 / 远程门户**
   - SMBv2、NFSv3 和 WebDAV 的真实目录/Range 读取已存在，是当前较可靠模块。
   - NFS 明确只支持 v3，纯 NFSv4 export 枚举未实现。
   - Range 处理缺少非法区间、后缀区间、多区间和 `416 Range Not Satisfiable` 校验。
   - 服务实际绑定 `0.0.0.0`，不仅是 `127.0.0.1`；远程写 API 没有配对码/会话鉴权。
   - 门户只支持 TVBox URL 和媒体 URL；没有 IPTV 文本/文件、NAS 凭据配置、二维码生成和 DLNA 受保护流桥接。

### P2：跨平台与工程完整性

1. **TV Focus First 尚未全量验证**：存在通用 `TvFocusWrapper`，但没有自动化规则证明所有页面交互元素都有显式 FocusNode。
2. **全量 i18n 未完成**：核心页面仍存在大量中文字符串常量；运行时语言切换只覆盖字典化文案。
3. **主题 Token 未全量落实**：播放器和页面仍大量使用 `Colors.white/black` 等直接颜色。
4. **跨平台构建证据不足**：当前测试集中在 Dart/Widget 和 Windows 行为，没有 Android、Android TV、iOS、macOS、Linux 的构建/集成验证。
5. **参考资产合规需要单独处理**：`analysis/` 含 APK、反编译文件和第三方仓库副本；发布前需要许可证、来源、分发边界和仓库体积审计。

## 4. 建议实施顺序

### 阶段 A：去除伪完成状态

1. 将 TVBox mock 源隔离为显式 demo adapter；生产源没有真实 runtime 时返回可诊断错误。
2. 禁止云盘模拟 URL、模拟 Token 和元数据模拟结果进入生产 UI。
3. 离线下载在未完成全部分片、解密和 remux 时不得标记 completed。
4. 给以上边界增加失败测试，防止以后再次把 mock 当作真实能力。

### 阶段 B：补齐可形成闭环的核心链路

1. IPTV：TVBox Live JSON -> XMLTV -> 回看插值 -> 线路吞吐评分 -> 播放器熔断。
2. TVBox：配置递归解析 -> QuickJS sandbox -> CatVod home/category/detail/search/play -> candidate 聚合。
3. 元数据：provider adapter -> 缓存 -> generation guard -> 详情页并行合并。
4. 下载：HLS master/media parser -> AES-128 -> 重试/校验 -> FFmpeg remux -> 任务持久化。

### 阶段 C：扩展外部设备与账号能力

1. 云盘逐供应商接入，并统一走安全存储、一次 401 刷新和 Range proxy。
2. DLNA 补齐 DMC 控制面，再实现 Windows/Android TV DMR。
3. WebDAV 同步升级为 v1 分文件、字段级 LWW、tombstone、ETag 与原子 MOVE。
4. WebView 嗅探作为独立高风险模块实现，设置 12 秒硬超时和交互式验证码升级。

## 5. 回归完成门槛

每个子系统只有同时满足以下条件才可从 README 的“规划能力”升级为“已实现能力”：

1. 不使用固定业务结果、示例域名或延时模拟。
2. 真实协议的成功、超时、鉴权失效、取消、资源释放均有测试。
3. UI 调用真实服务，并能展示失败原因与恢复动作。
4. `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test` 全部通过。
5. Windows 主力平台完成实际运行验证；平台相关能力还需对应目标平台构建或设备验证。

## 6. 重构优化落地记录 (2026-10-21 ADR-012~016 闭环)

| 领域模块 | 改造前问题 | 优化落地状态与证据 | 对应 ADR / 规范 |
| :--- | :--- | :--- | :--- |
| **TVBox / 爬虫** | 假 mock 列表、假 CCTV 回退、假 4K 仓 | **已彻底去模拟化**：清除假数据回退；落地纯 Dart 爬虫适配器 (`packages/source_providers/lib/tvbox/ports/`)；Android 原生 DEX 兜底增设安全免责弹窗并默认关闭；Windows 端严禁执行未知字节码；14 大测试套件 100% 通过。 | ADR-008, ADR-014 |
| **本地代理与网关** | 单端口 0.0.0.0 越权暴露 | **物理端口严格隔离**：抽取至独立纯 Dart 包 `packages/proxy_server`；`127.0.0.1:9978` 仅供本地回环播放；`0.0.0.0:9979` 按需开放为局域网远程配置门户，强制 6 位 PIN 码配对与会话鉴权。 | ADR-015 |
| **DLNA 投屏与接收** | DMC 与应用耦合、缺少 DMR 接收端 | **发送与接收端全解耦**：DMC 控制器抽取至 `packages/cast_sender`；DMR 接收端在 `packages/receiver` 中完整落地纯 Dart UPnP 守护进程，支持设备描述 XML、AVTransport、RenderingControl、DIDL 解析与 GENA 订阅。 | ADR-003, DMR-01~05 |
| **播放内核与杜比** | 双引擎概念含糊，存在实现风险 | **分期交付与调度落槽**：首发统一采用 `media_kit` (libmpv) 为全平台通用基底；完成 `PoC-10` 杜比与音频直通评估报告；设置页预置双引擎开关与 3 秒解码看门狗降级。 | ADR-002, ADR-013, PoC-10 |
| **多端 WebDAV 同步** | 单一文件覆写、明文保存凭据 | **分区与硬件安全加密**：按 `/JuYing/sync/v1/*.json.gz` 契约分文件同步；支持 ETag 并发检测、临时文件与原子 MOVE；WebDAV 凭据由 `SecureWebDavCredentialStore` 写入平台安全硬件密钥库。 | ADR-005, APP-12 |
| **离线下载管理器** | 直接将未解密 TS 命名为 .mp4 | **真 AES-128 解密与完整性校验**：支持 Master Playlist 选流、AES-128 动态解密、IV 解析、CBC 解密与分片完整性校验，拒绝非法的未支持 HLS 布局。 | ADR-005, P2 |
| **UI 与 TV 交互** | 颜色硬编码、缺少大屏遥控防抖 | **Apple 风格令牌收口**：落地 `packages/ui_kit`，提供 Cinema Dark 设计令牌；`TvFocusGlow` 支持 60ms 聚焦防抖与全局 D-Pad 导航；支持低性能设备毛玻璃实时降级为纯色半透明。 | ADR-010, ADR-016 |


