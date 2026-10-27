# zhuiju.me 对聚映的参考价值

调研日期：2026-10-27（Asia/Shanghai）。对象：[追剧么指南](https://zhuiju.me/)及其链接到的项目一手仓库。范围：聚映当前 Android 原生 View + Media3 版本；仅记录参考，不移植代码、不添加播放源或依赖。

## 结论与优先级

**有帮助，但主要价值是发现可读源码、学习源质量反馈和建立验证记录。** 该站是资源导航，不能视为聚映的统一播放 API，也不能把导航的推荐指数或“可访问”直接当作源接入依据。

建议按下面顺序研究；这是结合聚映低配 TV、单播放器和用户自行配置源的约束做出的判断，不是上游性能排名。

| 顺序 | 参考对象 | 对聚映最有价值的内容 | 建议落点 |
| --- | --- | --- | --- |
| 1 | FongMi/TV | TVBox 契约边界、直播切线与旧请求结果隔离 | `source:tvbox`、`feature:player`、既有兼容性测试 |
| 2 | WebHomeTV | 从实际搜索、详情、播放结果积累源质量反馈 | `core:data` 的源调度、搜索与换源策略 |
| 3 | iptv-api | 对用户配置的直播地址做有限取样和分阶段检测 | 先用于开发端验证，再决定是否提供端内诊断 |
| 4 | WebHomeTV2 / Silent1566 | 元数据匹配与可取消的详情预取 | 点播详情、海报补全；应晚于播放稳定性 |
| 后续 | Animeko、PanSou | 候选资源筛选、网盘搜索结果和检测状态表达 | 有明确需求后再研究；网盘仍暂不接入 |

FongMi、Kodi 等已有较详细的[播放源与 TV 功能参考](github-tv-source-references.md)，本文只补本次导航带来的新线索；Web 聚合产品还可对照 [LibreTV 评估](2026-10-26-libretv-assessment.md)。

## 当前聚映已有能力：以 10 月 27 日工作区为准

本次结合当前工作区读取结果做映射，含尚未提交的改动；不能用旧 Flutter 记录或 10 月 26 日调研中的待办推断当前缺口。以下是源码能力核对，不是设备验收结果。

| 当前已存在 | 本次参考带来的后续增量 |
| --- | --- |
| `searchUpdates` 已逐源/子站增量返回，按设备档位限制并发；`SearchViewModel` 会取消旧请求 | 研究真实请求反馈与源质量排序，不再立项重写“并发/增量搜索” |
| 源检查当前主要读取站点、分类、频道或目录数 | 明确“配置可读”与“可播放”的区别；需要时补分阶段检测记录 |
| `PlayerViewModel` 已顺序切换备用线路，并携带请求头与进度 | 补连续切台、迟到结果、错误分类等回归，不重复开发基本切线 |
| IPTV 已有 EPG、gzip 流式解析与缓存；同目录字幕、历史续播也已存在 | 研究边界样本、坏网表现和资源开销，不把这些已有功能列成新增需求 |
| TVBox 已有 CMS/Jar/JS/Python 基础契约 | 从多层仓库选择、完整 drpy、通用嗅探/代理、本地配置导入等已记录缺口按需选择 |
| 点播已有源封面和基础元数据；本次未找到 TMDB 集成 | 仅将可取消的外部元数据补全作为新候选，保留当前来源与播放身份 |

核对入口：[Repository 实现](../../core/data/src/main/kotlin/com/flytech/juying/core/data/DefaultRepositories.kt)、[搜索 ViewModel](../../feature/search/src/main/kotlin/com/flytech/juying/feature/search/SearchViewModel.kt)、[播放器 ViewModel](../../feature/player/src/main/kotlin/com/flytech/juying/feature/player/PlayerViewModel.kt)、[点播模型](../../core/model/src/main/kotlin/com/flytech/juying/core/model/Vod.kt)、[封面适配器](../../core/ui/src/main/kotlin/com/flytech/juying/core/ui/VodPosterAdapter.kt)、[当前点播与脚本兼容范围](../TVBOX_CCTV.md)。[TVBox 兼容修复记录](../FONGMI_COMPATIBILITY.md)含修复前差异，不能把整张旧表重新当作待办。

## 1. 导航自身：借鉴检测记录，不导入整站资源表

一手仓库现为 [laoma528/awesome-zhuiju-free](https://github.com/laoma528/awesome-zhuiju-free)，旧 `laoma2053` 地址会跳转。本次核对提交为 [`612e65bcda4b`](https://github.com/laoma528/awesome-zhuiju-free/commit/612e65bcda4bed9745535efed29276c161a5917b)。

- **已确认的检测边界**：README 说明检测只代表 GitHub Actions 节点当时的主页响应情况。脚本跟随重定向、发出带 Range 的 GET 后取消响应体，将可访问、访问受限与失败分开，保存 HTTP 状态、最终 URL、耗时、时间、尝试次数和错误；并非视频解码、登录或长播检测。[README](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/README.md)、[检测脚本](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/scripts/check-availability.mjs)
- **已确认的数据组织**：资源表将访问状态、评分、风险与人工验证分开；高评分条目也可能注明尚未独立验证播放/广告。贡献流程要求记录日期、网络环境，并区分主页访问和核心功能；验证记录独立保存。[资源结构](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/resources/resources.json)、[贡献说明](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/CONTRIBUTING.md)、[人工验证记录](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/reports/verifications.json)
- **聚映建议**：后续验证记录分别保留“地址可达 → 配置/列表解析 → 搜索/详情 → 播放解析 → 首帧/音频 → 持续播放”，同时记录样本、设备、网络和日期。401/403、限流、空结果、用户取消、格式不支持和解码失败应分开表达，避免统一显示“源失效”。这是聚映的候选验证方法，并非该导航已完成的能力。

资源列表适合作为调研索引。按[聚映工程约束](../../AGENTS.md)，不把其中第三方影视站点、网盘资源或 TVBox 接口合集加入默认配置；本次也未复制这些地址。

## 2. FongMi/TV：补齐契约与并发边界

**已确认**：当前 README 覆盖电视、手机、平板以及直播分组、节目表、线路切换等功能；本次读取的 `LivePlaybackController.cannotApply()` 在应用结果前检查待处理请求、请求对象与当前频道，防止旧请求影响新频道。[README](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/README.md)、[请求隔离源码](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/app/src/main/java/com/fongmi/android/tv/playback/live/LivePlaybackController.java#L287-L290)

**聚映建议**：对照既有 TVBox 兼容性文档与测试检查具体差异，优先验证子站路由、播放请求头、取消、备用线路以及连续换台时最后一次请求生效，只针对失败项补齐。原有 `SourceProvider` / `PlayItem` / `PlaybackManager` 分层继续保留。上游功能存在不代表聚映缺失，也不需要再建一套播放器抽象。

**不直接采用**：全量移植多内核、运行时和机型补丁。新增适配必须对应已复现问题；上游支持范围不等于聚映在 MX5 上已经验证。

## 3. WebHomeTV：源质量反馈比网页首页更值得参考

**已确认到源码**：`SiteHealthStore` 分别记录搜索、详情和播放成功/失败，包含最近搜索结果数、搜索/详情耗时及播放时间；评分为这些信号赋予不同权重，并支持对站点/候选排序和延迟持久化。README 还说明站点弹窗可保留用户配置顺序。[健康记录源码](https://github.com/webhtv/webhtv/blob/4e30ffaf219b1db15fe5662aeff6f9820e2b32bf/app/src/main/java/com/fongmi/android/tv/setting/SiteHealthStore.java)、[README](https://github.com/webhtv/webhtv/blob/4e30ffaf219b1db15fe5662aeff6f9820e2b32bf/README.md)

**聚映建议**：如果后续出现多源搜索慢、坏源反复重试的问题，先复用真实请求的成功率和耗时做本地反馈，不在启动时主动扫描全部源。搜索完成与可播放分开记；空结果、主动取消不直接算源故障。排序保留用户优先级，未知源仍有机会被选中。缓存数量、保存频率和过期策略应服从 `DeviceProfile`，不直接照搬上游评分常数。

**不直接采用**：HTML/JavaScript 首页、Native SDK 桥、远程托管和登录态同步。它们扩大了内存、生命周期及凭据处理范围；聚映当前原生 View 方向无需为这些功能改变架构。上面的“取消/空结果分类”等是聚映建议，不是对该上游所有调用链已正确处理的保证。

## 4. Guovin/iptv-api：参考有限取样，不把采集平台塞进盒子

**已确认到源码与测试文件**：README 将项目定位为直播地址采集、校验、测速和播放列表生成工具；`utils/speed.py` 对播放列表、连续流取样和分片数量设限，并区分网络取样与媒体探测。`test_speed_limits.py` 用本地连续响应覆盖 HEAD 失败后 GET 回退仍受字节限制的情况。[README](https://github.com/Guovin/iptv-api/blob/6ea026fd8522e3755f7197a77e21218c2f6a7514/README.md)、[测速实现](https://github.com/Guovin/iptv-api/blob/6ea026fd8522e3755f7197a77e21218c2f6a7514/utils/speed.py)、[边界测试](https://github.com/Guovin/iptv-api/blob/6ea026fd8522e3755f7197a77e21218c2f6a7514/tests/test_speed_limits.py)

**聚映建议**：先作为开发端 IPTV 排障方法：配置解析成功后，分别检查清单、少量媒体分片、编码信息和目标设备首帧。网络探测应限制并发、字节和总时长，使用真实播放头信息，允许取消；检测结论记录所在网络，不能把云端测速结果永久作为本地线路优先级。

**不直接采用**：全量采集、定时测速、FFmpeg 截图和转码常驻低配盒子。读取了上游测试不等于执行通过；媒体探测成功也不等于 Media3/硬件解码与音频输出成功。

## 5. Silent1566/WebHomeTV2：海报与元数据补全的边界

**已确认到源码**：`TmdbMatcher` 结合标题、年份、媒体类型及季信息选择候选，并将鉴权失败/取消与普通匹配失败区别处理；`TmdbDetailPrefetch` 按 TMDB id 与媒体类型复用任务，替换时取消旧任务。[匹配器](https://github.com/Silent1566/webhtv/blob/edf04f9b5048b6b5bc38c53333ac3c7d62f00265/app/src/main/java/com/fongmi/android/tv/ui/helper/TmdbMatcher.java)、[预取管理](https://github.com/Silent1566/webhtv/blob/edf04f9b5048b6b5bc38c53333ac3c7d62f00265/app/src/main/java/com/fongmi/android/tv/ui/helper/TmdbDetailPrefetch.java)

**聚映建议**：元数据仅补全展示，不替换来源身份和播放路由。先用源自身海报；需要补全时异步请求、缓存结果、离页取消，失败保持原条目可用。重点防同名翻拍、电影/剧集、不同季和特别篇误匹配；不因候选评分高就静默覆盖标题或选集。TMDB 接入凭据、使用条款和署名要求应在真正接入时另行核实。

**不直接采用**：为了海报墙引入整个分支的多内核、WebHome、账户和同步体系。本轮没有调用 TMDB API，也未验证图片匹配准确率。

## 6. 后续候选：Animeko 与 PanSou

| 对象 | 本次已确认 | 对聚映的有限参考 | 暂缓原因 |
| --- | --- | --- | --- |
| [Animeko](https://github.com/open-ani/animeko) | README 说明 Kotlin/Compose Multiplatform、多数据源与观看进度；`MediaSelectionDecider` 按分辨率、字幕语言、来源偏好等筛选候选 | 候选筛选与 UI 分离；未来选源可优先匹配用户明确的画质/语言要求，不静默降级 | 不移植 Compose、BT、完整弹幕/缓存体系；当前没有为这些能力增加模块的必要 |
| [PanSou](https://github.com/fish2018/pansou) | README 提供搜索、分享链接检测和健康检查 API；检测结果区分有效、失效、密码问题、不支持和不确定，并带检测/过期时间 | 如果以后支持用户自建网盘搜索服务，可参考结果类型、来源、鉴权及检测状态表达 | 搜索到分享链接不等于取得播放直链；网盘暂不接入，也不把公共实例变成内置依赖 |

来源：[Animeko README](https://github.com/open-ani/animeko/blob/2f33ea346ec43f303827579d8659358dd3ecf98b/README.md)、[候选选择源码](https://github.com/open-ani/animeko/blob/2f33ea346ec43f303827579d8659358dd3ecf98b/app/shared/app-data/src/commonMain/kotlin/domain/media/selector/MediaSelectionDecider.kt)、[PanSou API 文档](https://github.com/fish2018/pansou/blob/221665fb2c9279f22af4684ea2d8c0c331eac1cc/README.md)。PanSou 本轮只核实文档契约，未调用服务或审计插件。

## 复用前的许可证记录

以下是实际读取的根许可证快照，不代表所有第三方文件、依赖或素材采用同一许可，也不作整仓兼容性结论。

| 项目 | 本次提交 | 观察到的根许可 |
| --- | --- | --- |
| awesome-zhuiju-free | `612e65bcda4b` | [CC BY 4.0](https://github.com/laoma528/awesome-zhuiju-free/blob/612e65bcda4bed9745535efed29276c161a5917b/LICENSE) |
| FongMi/TV | `123cc086159b` | [GPLv3](https://github.com/FongMi/TV/blob/123cc086159b0f13bf54bdf64bacbc259ca47c88/LICENSE.md) |
| webhtv/webhtv | `4e30ffaf219b` | [GPLv3](https://github.com/webhtv/webhtv/blob/4e30ffaf219b1db15fe5662aeff6f9820e2b32bf/LICENSE.md) |
| Silent1566/webhtv | `edf04f9b5048` | [GPLv3](https://github.com/Silent1566/webhtv/blob/edf04f9b5048b6b5bc38c53333ac3c7d62f00265/LICENSE.md) |
| Guovin/iptv-api | `6ea026fd8522` | [AGPLv3](https://github.com/Guovin/iptv-api/blob/6ea026fd8522e3755f7197a77e21218c2f6a7514/LICENSE)；GitHub 元数据为 `NOASSERTION`，本表依据文件正文 |
| Animeko | `2f33ea346ec4` | [AGPLv3](https://github.com/open-ani/animeko/blob/2f33ea346ec43f303827579d8659358dd3ecf98b/LICENSE.txt) |
| PanSou | `221665fb2c92` | [MIT](https://github.com/fish2018/pansou/blob/221665fb2c9279f22af4684ea2d8c0c331eac1cc/LICENSE)；仓库简介另有非盈利表述，实际复用前须澄清适用范围 |

## 后续执行时的验收入口

- **源质量反馈**：使用成功、空结果、超时、取消、解析失败等固定样本；证明未知源和用户指定源不会被错误永久排除，日志不带 Cookie/Token。
- **直播检测**：准备合法/自有的普通 HLS、主清单、分片失败、请求头要求及慢响应样本；证明总时长/字节有界、取消有效；再在 `qytech6666` 验首帧、音频、切台与长播。
- **元数据补全**：同名不同年份、电影/剧集、季/特别篇、无结果、401/限流、取消与旧回调样本；证明不阻塞列表和播放，不覆盖错误条目。
- **TVBox 兼容**：以已有兼容性文档和测试的实际缺口为起点，验证分类→搜索→详情→选集→解析→播放，以及子站隔离和请求头传递。

## 验证边界

本轮核实到公开站点、仓库文档及以上明确列出的源码/测试文件；没有安装这些项目、运行其测试、测试第三方播放源或在 MX5 上对比性能。所有优先级和适配方案均为后续建议，不能据此宣布聚映已接入或支持相应功能。外部链接、仓库分支及服务策略可能变化，开始实现时以固定提交为起点重新核对。
