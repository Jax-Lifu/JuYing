# 跨平台播放器的内容源策略研究

核查日期：2026-10-16。范围为 Kazumi、Animeko、Miru 三个项目的官方仓库、文档及发布记录；仅阅读公开资料，没有安装软件、扩展或订阅，也没有验证第三方站点的实际播放成功率。

## 对 JuYing 的结论

建议收缩默认启用的混杂节点，保留兼容且经过验证的 TVBox 导入能力。是否删除某个配置应依据当前平台的协议兼容性和实际播放结果决定。本研究没有逐项测试 JuYing 现有配置，不能据此认定整份配置已经失效。

这三个项目主要提供采集规则、扩展运行环境、资源匹配和播放器。规则仓库或扩展仓库存在，不代表其中每个站点当前都能访问、每一集都能播放，或项目附赠了长期稳定的片库。Animeko 也明确说明客户端本身不提供视频资源。[Animeko README][anime-readme]

## 核查快照与 Windows 支持

| 项目 | 代码快照 | Windows 证据与限制 |
| --- | --- | --- |
| Kazumi | `main`：`025dcb5c2f62db881382c72f191d08b49a9feb41` | README 要求 Windows 10+；2026-10-14 发布 2.3.9，提供 Windows ZIP/MSIX。源的反盗链仍可能影响外部播放器。[README][kazumi-readme]、[发布页][kazumi-release] |
| Animeko | `main`：`008825b8540750d1323552cec2fa4bb8610a56a4` | 支持 Windows；2026-10-13 发布 v6.3.0，提供 x86_64/aarch64 ZIP。主线晚于该发行版，下面的新机制属于该源码快照，不保证全部已进入稳定包。[README][anime-readme]、[发布页][anime-release] |
| Miru | 旧 `miru-app/dev`：`8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0`；新 `miru-alpha/main`：`e17007116d8dea1c2d50c4332a0c01f2f3e177d3` | 旧版 v1.8.1 发布于 2024-01-19，有 Windows 安装包/ZIP；重写版 2026-10-16 的 `v2.0.1-alpha+100002` 有 Windows ZIP，但明确为预发布。不能把旧版介绍、重写版源码和稳定能力混为一谈。[旧版发布][miru-release]、[Alpha 发布][miru-alpha-release] |

以上是官方支持与包清单证据，没有进行 Windows 安装、解码或播放验收。

## 三种路线

### Kazumi：用小型规则描述搜索、线路与剧集

它主要面向番剧。经典规则通过 XPath 从网页提取搜索结果和分集，当前源码也支持 API 模式：请求模板、请求头和 JSONPath 可以描述搜索与剧集列表。因此“只有五行 XPath”已经不足以概括当前能力。[README][kazumi-readme]、[API 配置模型][kazumi-api]

源搜索会区分等待、成功、无结果、需要验证和错误，并提供按源重试。`PluginValidityTracker` 只记录本次启动后某规则是否成功返回过搜索结果；它没有证明视频首包、解码或持续播放健康。选源页仍让用户选择具体结果。[搜索服务][kazumi-search]、[有效性记录][kazumi-validity]、[选源页][kazumi-source]

适合借鉴：规则字段少、可以独立测试搜索与选集、错误状态清楚。代价是页面结构、请求头或站点接口变更后仍需维护规则；换成 XPath/API 并不能自动修好上游失效。遇到播放器不兼容时，官方 README 提供 WebView 播放作为兼容方案。[README][kazumi-readme]

### Animeko：元数据与候选分开，再自动选对一集

当前主线支持 CSS Selector/正则、JSON API/JSONPath、RSS，以及 Jellyfin、Emby、Ikaros 等媒体库适配；也支持 BT。自建媒体库是用户自己的服务，不等于公共网盘片库。源码把“列出站点内容供手选”和“自动匹配某部作品某一集”分开，允许某源仅用于浏览。[数据源文档][anime-sources]

选源机制比“谁先返回就播放谁”更完整：本地缓存优先，随后考虑记忆的源；Web 候选按作品/剧集匹配和源或线路等级选择，默认分 5 秒、15 秒阶段逐步放宽条件。15 秒是允许降级的时点，不是查询总超时。播放失败换源只尝试 Web，保留失败黑名单，并避免覆盖等待期间的手动选择。[选择器文档][anime-selector]

这些等级首先来自源/线路配置，不能描述成通过长期测速自动产生的健康分。BT 则依赖 P2P 获取数据，客户端支持 BT 不代表某个资源当前存在可用上传者；官方说明使用 BT 时会自动做种。[数据源文档][anime-sources]、[README][anime-readme]

适合借鉴：实体和候选分离、错季错集过滤、记住选择、失败后有限换源。代价是匹配规则和回归样本需要持续维护；不宜直接照搬 Kotlin/Compose、VLC 或整套 BT 引擎到 JuYing 的 Flutter/media_kit 架构。

### Miru：扩展生态，并限制默认搜索范围

旧 `miru-app` 使用 JavaScript 扩展，Windows 通过 QuickJS 执行；模型可返回 HLS、MP4 或 torrent，并携带请求头。[旧版扩展运行器][miru-runtime]、[返回模型][miru-model]

当前 Miru Alpha 是重写项目：Flutter 前端与 Go 后端经 gRPC 通信，扩展支持 JavaScript 和 Go/Scriggo，媒体通过统一核心及本地代理处理，包含 BT 引擎。它仍属 Alpha；引入这套运行环境将增加跨语言构建、打包和扩展兼容成本。[Alpha README][miru-alpha-readme]

值得借鉴的是当前主线默认仅搜索用户置顶的扩展，可以改为全部或指定集合；搜索聚合分别记录完成数、失败源，并支持仅重试失败源。排序可按相关性、更新时间或源优先级。这里确认的是搜索范围与失败可见性，本次没有确认持续播放健康评分或 Animeko 式的自动跨源换集机制。[搜索范围][miru-scope]、[聚合与重试][miru-search]

## 在 JuYing 中如何取舍

以下为研究建议，不表示功能已经实现。项目已有约束要求 `MediaItem` 与 `PlaybackCandidate` 分离，可沿用这条边界，不必因参考外部项目增加第二套领域模型。

| 建议 | 解决的问题 | 代价与验收边界 |
| --- | --- | --- |
| 默认仅启用少量经过当前 Windows 验证的源；保留可选导入 | 避免一次搜索大量不可用节点 | 少量源覆盖面较窄，需要维护明确名单；不擅自删除用户订阅 |
| 导入时区分平台不兼容、网络失败、无内容、需要认证/验证 | 避免把所有失败归成“源坏了” | 需要每种适配器声明能力并返回可解释错误；无法运行的源不应进入自动候选 |
| 分开记录配置可读、搜索成功、选集正确、媒体可读、实际播放成功 | 避免 HTTP 200 或搜到片名就显示“可用” | 最近验证时间、平台和失败阶段必须保留；轻量探测不能代替真实播放 |
| 优先当前集的精确匹配和用户记忆；失败候选在当前会话隔离 | 减少反复点坏线路、自动播错季 | 需要稳定候选标识、有限重试和取消机制；不得覆盖用户新选择 |
| 官方内容与用户自有媒体作为明确入口，第三方规则作为可选扩展 | 让默认体验有可解释的来源与边界 | 官方内容覆盖有限；NAS/自建库需用户已有媒体和服务 |

不建议为了“节点更多”立即引入新脚本引擎、BT 或公共网盘聚合。上述三条路线中，本次确认的核心能力没有覆盖一套统一的公共网盘搜索与 Token 保活服务；扩展可编程也不等于这些功能已经可用。若以后确有此需求，应单独核验授权、登录、直链时效和跨平台播放，不能作为修复 TVBox 节点失败的默认替代方案。

优先顺序建议：先缩小默认范围并说明失败原因，再做好同一作品的候选筛选与换源；只有现有适配器无法表达实际需要的来源时，再增加一种规则或协议。

[kazumi-readme]: https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/README.md
[kazumi-release]: https://github.com/Predidit/Kazumi/releases/tag/2.3.9
[kazumi-api]: https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/lib/plugins/api_rule_config.dart
[kazumi-search]: https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/lib/services/plugin/plugin_search_service.dart
[kazumi-validity]: https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/lib/services/plugin/plugin_validity_tracker.dart
[kazumi-source]: https://github.com/Predidit/Kazumi/blob/025dcb5c2f62db881382c72f191d08b49a9feb41/lib/pages/info/source_sheet.dart
[anime-readme]: https://github.com/open-ani/animeko/blob/008825b8540750d1323552cec2fa4bb8610a56a4/README.md
[anime-release]: https://github.com/open-ani/animeko/releases/tag/v6.3.0
[anime-sources]: https://github.com/open-ani/animeko/blob/008825b8540750d1323552cec2fa4bb8610a56a4/docs/contributing/code/media/media-source.md
[anime-selector]: https://github.com/open-ani/animeko/blob/008825b8540750d1323552cec2fa4bb8610a56a4/docs/contributing/code/media/media-selector.md
[miru-release]: https://github.com/miru-project/miru-app/releases/tag/v1.8.1
[miru-runtime]: https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/lib/data/services/extension_service.dart
[miru-model]: https://github.com/miru-project/miru-app/blob/8599d0dbfbb1c1d86dcfa3d8d78e4c438d3fe2c0/lib/models/extension.dart
[miru-alpha-release]: https://github.com/miru-project/miru-alpha/releases/tag/v2.0.1-alpha%2B100002
[miru-alpha-readme]: https://github.com/miru-project/miru-alpha/blob/e17007116d8dea1c2d50c4332a0c01f2f3e177d3/README.md
[miru-scope]: https://github.com/miru-project/miru-alpha/blob/e17007116d8dea1c2d50c4332a0c01f2f3e177d3/lib/provider/search/search_page_provider.dart
[miru-search]: https://github.com/miru-project/miru-alpha/blob/e17007116d8dea1c2d50c4332a0c01f2f3e177d3/lib/provider/search/global_search_provider.dart
