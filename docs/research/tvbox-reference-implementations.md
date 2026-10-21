# TVBox 参考实现与 Windows 兼容边界

调研日期：2026-10-16。范围：上游公开文档及固定版本源码；不收集内容源地址，不修改聚映配置或产品代码。

**建议保留 TVBox 接入，但收缩默认启用范围，按实际运行能力标注站点。** 能导入配置、能搜索、能取得候选、能读取媒体字节、能解码播放是不同验收层级。其他播放器的可用性依赖完整的运行宿主和播放契约，不能通过换一份大配置直接复制。

## 当前项目证据

本节为主审计任务提供的本机结果，非本报告独立复测：

- 当前持久化配置有 447 个站点，其中 426 个为 `type:3`，约 95%；382 个使用 `csp_` API、387 个关联 JAR、23 个 API 路径以 `.js` 结尾。这些是不同维度，不能相加；不能用包含 `.js` 的字符串计数把 `.json` 误算成脚本。
- 现有三项 live 测试在本轮通过：xhz 中的 Bili 链路、4k 中指定的 MacCMS 链路、DC 中指定的 T4 链路均获得候选并读取到非空首块。
- 同轮 DC 仓库展开有一个返回 HTML 而非 JSON、三个子仓超时或失败，证明上游可达性问题与客户端能力问题同时存在。
- 这些结果支持保留可验证的子集；没有证明全部节点可用，也没有证明上述候选已通过播放器画面、音轨、拖动和连续播放验收。

## 参考项目身份与版本

| 项目 | 本次核实的材料 | 可借鉴范围 |
| --- | --- | --- |
| FongMi/TV | [固定提交 b49b702](https://github.com/FongMi/TV/tree/b49b7027639edd42c7209651f9f0dab7150ae7ba)，提交时间 2026-10-11 | Android TV/手机端的配置、Spider、解析和代理协作。README 的 Windows 构建说明指在 Windows 构建 Android 应用，不能作为 Windows 客户端证据。 |
| q215613905/TVBoxOS | [固定提交 ab11d28](https://github.com/q215613905/TVBoxOS/tree/ab11d289e09963a9daf65ca7f6b7a9a8cbe184e1)，提交时间 2026-09-14 | 当前可访问的 TVBoxOS 实现，用来交叉核对站点类型和播放请求；不将它冒充为已不可访问仓库的官方新地址。 |
| CatPawApp/CatPawOpen | [固定提交 b956aed](https://github.com/CatPawApp/CatPawOpen/tree/b956aedabe5f624f1e96c8d21c8866617a0f71c1)，提交时间 2025-01-17 | 可确认的是 Node.js 扩展工程和 CatOpen 风格路由，不能据此确认整个 Flutter/Windows 播放客户端的源码或兼容性。 |

本次访问 `TVBoxOS/TVBox`、`TVBoxOS/TVBoxOSC`、`CatVodTVOfficial/TVBoxOSC`、`catvod/CatVodOpen` 和 `FongMi/CatVodOpen` 均返回 404；只能说明这些地址在本次环境下不可访问，不能判断删除、改名或权限原因。

## 播放器实际怎样接入内容

FongMi 的公开说明将应用定位为播放器，内容通过外部配置接入。配置中的站点定义了获取分类、搜索、详情和播放结果的接口或脚本；配置本身通常不等于最终媒体清单。[FongMi README](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/README.md)、[配置文档](https://fongmi.github.io/TV/config/)

| `sites[].type` | 参考实现的含义 | Windows/Dart 端的实际要求 |
| --- | --- | --- |
| 0 | HTTP XML 采集接口 | XML 解析、分类/分页/详情字段映射，以及播放结果处理。 |
| 1 | HTTP JSON 采集接口，常见于 MacCMS | JSON 结构适配；部分接口的剧集值仍是页面或解析输入，不能一律当媒体直链。 |
| 3 | 本地 Spider 宿主；FongMi 再按 `.py`、`.js`、`csp_` 分流 | 分别需要 Python、JS 或 Android CatVod/JAR 环境；`type:3` 本身不表达跨平台可执行性。 |
| 4 | HTTP 扩展 JSON/T4，Spider 逻辑由远端服务执行 | 客户端不执行远端 JAR，但必须匹配完整的 HTTP 请求与响应契约。 |

类型分流见 [FongMi SiteApi](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/SiteApi.java#L47-L110) 和 [BaseLoader](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/loader/BaseLoader.java#L38-L63)；TVBoxOS 也分别处理 Spider、0/1、4 的播放请求：[SourceViewModel](https://github.com/q215613905/TVBoxOS/blob/ab11d289e09963a9daf65ca7f6b7a9a8cbe184e1/app/src/main/java/com/github/tvbox/osc/viewmodel/SourceViewModel.java#L1121-L1260)。表格是这些实现的行为归纳，不是所有分支都保证一致的正式标准。

### JAR 与 JS 兼容性不能混为一谈

FongMi 用 `dalvik.system.DexClassLoader` 装载 JAR，再实例化 `com.github.catvod.spider.*` 并传入 Android Context。由此可确定：普通 Windows Dart 进程没有这套 Android 宿主；仅下载 JAR、读取类名或补 QuickJS 都不能执行同一份 Spider。[JarLoader](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/loader/JarLoader.java#L53-L130)

即使节点使用 JS，还要匹配宿主提供的 HTTP、本地存储、模块解析、全局函数和代理协议。FongMi QuickJS 初始化会注入这些能力，并尝试从 DEX 加载可选的 `com.github.catvod.js.Function`。因此“使用同一个 JS 引擎”只能证明语法执行基础一致，不能证明每个源依赖的 API 都齐全。[QuickJS Spider 初始化](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/quickjs/src/main/java/com/fongmi/quickjs/crawler/Spider.java#L161-L205)

CatPawOpen 的 Node 工程说明仍标记 WIP，并说明跨平台运行时限制；其 `/config` 返回 `video/read/comic/music/pan` 分类，站点路由形如 `/spider/{key}/{type}`。这是另一套宿主/插件协议的证据，不能把其中的 `type` 直接解释成 TVBox 的站点类型，也不能将 Node 插件当 QuickJS 模块直接执行。[Node README](https://github.com/CatPawApp/CatPawOpen/blob/b956aedabe5f624f1e96c8d21c8866617a0f71c1/nodejs/readme.md)、[router.js](https://github.com/CatPawApp/CatPawOpen/blob/b956aedabe5f624f1e96c8d21c8866617a0f71c1/nodejs/src/router.js#L19-L89)

### 取得 URL 之后，还有完整的播放契约

- **T4 参数**：FongMi 的播放调用发送 `play`、`flag`，通用调用附带站点 `extend`；分类筛选另用 URL-safe Base64 的 `ext`。不应丢失线路标记，也不能把两种扩展参数混用。[SiteApi 请求](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/SiteApi.java#L39-L44)、[分类](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/SiteApi.java#L91-L110)、[播放](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/SiteApi.java#L143-L189)
- **解析模式**：`parses[].type` 是另一组枚举。FongMi 的 0 为 WebView、1 为 JSON、2/3 为 JAR 扩展解析、4 为组合解析，不能复用 `sites[].type` 的解释。播放结果的 `parse`、`playUrl`、`flag` 等决定后续流程。[ParseJob](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/player/parse/ParseJob.java#L63-L137)
- **Headers 与 Cookie**：FongMi 会给 WebView 设置 UA/Cookie，从拦截到的媒体请求提取请求头，再随解析成功结果交付。只保存裸 URL 会丢失防盗链或会话上下文。[CustomWebView](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/ui/custom/CustomWebView.java#L104-L129)、[结果回传](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/ui/custom/CustomWebView.java#L206-L217)
- **本地代理**：Spider 可依赖本机 `/proxy`；FongMi 将请求参数和请求头交给对应 Spider，并保留代理返回的状态码、媒体类型、流和响应头。应将其视为播放链的一部分，不能仅返回一个没有服务承接的回环地址。[Proxy](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/server/process/Proxy.java#L21-L49)、[宿主分发](https://github.com/FongMi/TV/blob/b49b7027639edd42c7209651f9f0dab7150ae7ba/app/src/main/java/com/fongmi/android/tv/api/loader/BaseLoader.java#L79-L84)

## 对聚映的最小建议

1. **保留配置，调整默认可用范围。** 首先保留本轮已验证的 HTTP/MacCMS、T4 和明确支持的专用 Dart 适配器。当前 JS 宿主尚不完整，不列入已支持范围。需要 Android JAR 的条目可保留为已导入但当前平台不支持，避免让用户逐个等待超时；不要批量删除用户导入项。
2. **能力判断具体到站点依赖。** 根据 `type`、`api`、JAR、脚本方言及实际适配器确定能力；`csp_` 默认意味着原生 Spider 依赖，但已有专用 Dart 适配器的站点应单独识别。成功解析配置不能把全部条目标成可播放。
3. **先修契约，再扩节点量。** 保留播放结果中的解析要求、线路标记、请求头、Cookie 和代理归属；让不支持、网络失败、空结果、解析失败、媒体请求失败分别可定位。界面只需清楚告诉用户该节点当前是否可用及原因，不必暴露底层术语。
4. **按完整链路验收。** 每类选择少量可重复验证的站点，分别验证配置、分类/搜索、详情/剧集、播放解析、媒体请求和实际解码；同时覆盖取消/换集后旧结果不能覆盖新状态、拖动和必要的多请求头场景。
5. **将扩大 JAR 兼容列为独立决策。** 若将来明确要求 Android TVBox JAR 覆盖率，再比较 Android 专用宿主与受控远端 T4 服务；它们分别增加平台维护和服务运维成本，不应在当前 Windows 故障排查中顺手引入。

上面的排序是基于当前站点分布与已验证链路的工程建议，不是对全部第三方源的可用性承诺。本报告没有运行上游 Android APK，也没有运行 CatPaw Windows 客户端。
