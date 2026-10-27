# LibreTV 对聚映的参考价值

调研日期：2026-10-26（Asia/Shanghai）。范围：上游默认分支源码、维护状态与聚映 Android 原生约束的适配判断；没有运行上游、探测第三方媒体源或移植代码。

## 结论

**有帮助，主要在聚合搜索、订阅状态和播放失败交互；适合作为业务规则与测试样例参考，直接移植收益较低。** 当前 LibreTV 是 Next.js 服务端与浏览器播放器组成的 Web 应用，不能替代聚映的 View/RecyclerView、Media3/SurfaceView、协议 DataSource 和 D-Pad 焦点体系。[技术栈](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/package.json#L15-L28)

## 本次快照

| 项目 | 核对结果 |
| --- | --- |
| 默认分支 | `main`，未归档；这是本次 GitHub API 查询的状态 |
| 固定提交 | [`deb72fa01f199abbb6e404c4a3e976aabfe4c96c`](https://github.com/LibreSpark/LibreTV/commit/deb72fa01f199abbb6e404c4a3e976aabfe4c96c)，2026-10-24 05:26:08 UTC |
| 最新正式发布 | [`v2.21.0`](https://github.com/LibreSpark/LibreTV/releases/tag/v2.21.0)，2026-10-23 10:28:07 UTC；未验证发布包运行 |
| 技术栈 | Next.js 15、React 19、TypeScript、ArtPlayer、hls.js、mpegts.js、Dexie/IndexedDB |
| 当前许可证 | [`package.json` 声明 AGPL-3.0-or-later](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/package.json#L1-L6)，[根 LICENSE 为 AGPL v3](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/LICENSE#L1-L6)；不能沿用旧版许可印象 |

## 值得借鉴的实际实现

### 1. 搜索先展示已完成的来源，失败来源单独反馈

每个来源有总超时，先抓第一页，再按 `pagecount` 和配置上限抓后续页。`?stream=1` 通过 NDJSON 逐源返回结果，最终再发聚合结果；单个来源失败不要求整个搜索失败。这是聚映实现全源搜索时最直接的参考。[来源搜索与取消](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/app/api/search/route.ts#L54-L150)、[逐源返回](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/app/api/search/route.ts#L185-L260)

卡片按去首尾空白后的完整名称聚合；同名存在多个年份时拆分，缺年份条目另成一组，只有单一年份时才并入。它能减少重复卡片，但不是可靠的跨站作品识别：同名不同作品、季数与剪辑版仍需明确规则。[聚合函数](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/video-card.tsx#L40-L66)

**适配边界**：上游最多接受 50 个搜索源并直接 `Promise.all`，源内分页也并行。聚映应复用 `DeviceProfile` 的并发预算，不能把服务端并发参数照搬进盒子。[源数量与并发](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/app/api/search/route.ts#L209-L227)

### 2. 订阅失败保留旧内容，刷新有数量和并发限制

自动刷新只在打开站点时执行，跳过离线或后台标签页；一轮最多 5 个订阅、并发 2 个，连续失败 3 次后暂停自动刷新。同步失败保留旧数据，鉴权错误不计为订阅失败。可借鉴的是“旧内容仍可用、行内显示失败、手动可恢复”的规则，具体阈值应按聚映使用方式调整。[同步失败规则](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/subscription-sync.ts#L26-L58)、[刷新护栏](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/subscription-sync.ts#L69-L149)

点播源搜索连续失败 2 次后会暂停参与搜索，处罚时长依次为 30 分钟、24 小时、长期；成功会清除停用标记并降低处罚级别。聚映可参考健康状态与手动恢复入口，但需要先区分设备离线、账号失效与真正的源故障，避免一次家庭网络问题惩罚全部来源。[规则常量](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/store.ts#L156-L190)、[状态更新](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/store.ts#L705-L758)

### 3. 播放失败先有限恢复，再给用户明确出口

恢复策略区分网络错误、媒体错误和格式硬失败；默认网络重试 3 次并指数退避，媒体恢复最多 2 次，定时任务在销毁时取消。独立策略有对应单测，适合借鉴测试场景和状态划分。[策略](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/playback-recovery.ts#L25-L133)、[测试](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/playback-recovery.test.ts#L13-L104)

这里的 `switch-source` 决策并不等于自动找到最佳来源：播放中失败会调用回调弹换源面板，起播失败则显示错误。hls.js 的 `recoverMediaError`、音频 codec 切换与浏览器代理回退也不能原样搬到 Media3。[调用方行为](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/player-shell.tsx#L419-L458)

### 4. 换源候选值得参考，但测速和续播能力要分清

候选来源先搜索标题，优先完全同名，其次标题前缀；随后读取详情与集数，保留当前来源置顶，其余按详情请求耗时排序。关闭面板会取消请求，失败可重新探测。[候选与取消](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/switch-source.tsx#L102-L177)

- **测速是详情接口响应耗时**，不是视频首帧、实际码率或持续播放稳定性测试。[计时实现](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/client-api.ts#L213-L221)
- **跨源切换只保留集数下标**，目标集数不足则回到第 1 集；切换参数没有携带当前播放秒数，也没有按集名重新对应。[切换实现](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/switch-source.tsx#L243-L258)
- **已有历史续播以来源、影片、集数为键**，播放页优先读 URL 时间，其次读本机 IndexedDB；这不等于跨来源、跨设备进度同步。[进度键](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/db.ts#L148-L159)、[恢复逻辑](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/app/watch/page.tsx#L158-L165)
- **画质另有探测**：读取清单或有限分片前缀提取分辨率，失败显示未知；它没有证明目标设备可解码或能够流畅播放。[探测边界](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/quality-probe.ts#L13-L44)

### 5. 直播节目单与空状态可补充交互规则

EPG 面板按 `epgUrl + tvgId` 查询，缺配置、失败重试、缓存和当前时间更新均有明确处理。可参考这些状态，供聚映直播界面落地。[EPG 面板](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/live-epg-panel.tsx#L28-L59)

解析器不应直接替换聚映现有实现：上游 M3U 仅接受 HTTP(S)，忽略 `EXTVLCOPT`，按 URL 去重；聚映还需要同频道多线路、请求头和局域网协议。XMLTV 虽按时间窗裁剪并按频道索引，但读取压缩输入后整段解压再扫描，不能当成低内存 Android 流式解析方案。[M3U](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/m3u-parser.ts#L26-L100)、[XMLTV](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/xmltv.ts#L73-L91)

## 不宜照搬的部分

1. **TVBox 兼容不是完整 Spider 引擎**。它导入可直连的 CMS JSON 接口和普通 M3U，跳过 Jar/JS/Python Spider、真正的 XML 接口等不支持项，并统计原因。值得参考“可导入多少、跳过多少、为何跳过”的反馈；不能把它当作补齐聚映全部 TVBox 类型的方案。[导入范围](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/tvbox-parser.ts#L11-L43)、[过滤实现](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/tvbox-parser.ts#L384-L440)
2. **CMS 详情没有保留全部播放线路**。`vod_play_url` 按 `$$$` 分组后，取第一个包含 m3u8 的组，否则取第一组。聚映已有 `PlayLine` 与请求头模型，应保留完整组和集名，不能照搬成单组 URL 数组。[解析实现](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/lib/cms-parser.ts#L54-L69)
3. **Web 代理与部署不是 Android 必需层**。其服务端承担请求、浏览器跨域和代理回退；聚映本机网络链路不应为复用这套前端而新增 Node 服务。只有未来明确需要家庭 Web 客户端时，才值得单独评估部署集成。[运行依赖](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/package.json#L7-L28)、[播放器代理回退](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/player-shell.tsx#L427-L440)
4. **主题只有浅色、深色、跟随系统**。本次读取的主题与 EPG 组件中未发现可复用的多语言层；这不能提供聚映 V2 简繁英与纯黑主题的现成原生实现，也不等于做了全仓国际化审计。[主题](https://github.com/LibreSpark/LibreTV/blob/deb72fa01f199abbb6e404c4a3e976aabfe4c96c/src/components/theme.tsx#L10-L40)
5. **直接复制代码先核对许可**。当前上游标注 AGPL-3.0-or-later，聚映工程约束为 GPL-3.0。本文只确认所读许可文本，未作完整兼容性审查；借鉴业务规则与重新实现不等于可以忽略复制代码、依赖和分发的许可条件。

## 聚映的具体落点

本地代码由本轮主线程核对；以下区分已有底层能力和仍待实现的界面，不把设计稿当成功能完成。

| 建议顺序 | 聚映现状与落点 | 参考方式 |
| --- | --- | --- |
| 1 | `TvboxSource` 的点播分类、列表、详情、搜索和解析仍为 TODO | 优先参考 CMS JSON/type 1 链路的响应解析与坏数据样例，保留多线路、集名和请求头；type 0/XML 需要另行实现，不能由此项目补齐 |
| 2 | `DefaultVodRepository.searchAll` 已有按 SEARCH 能力并发搜索、每源 8 秒超时和单源失败隔离，但等待全部完成才合并；`SearchFragment` 仍为界面骨架 | 在现有 Repository 上补有界并发、逐源状态和增量显示，不另建搜索框架 |
| 3 | 源注册与配置已有统一入口 | 在 `core:data` 与源管理界面增加必要的刷新/健康状态；失败保留旧内容、可手动恢复 |
| 4 | 聚映已有 `sourceId/ref` 路由与 `PlayLine` 模型 | 同作品分组用于比较候选，保留真实来源标识；不要仅凭同名就自动互换影片或集数 |
| 5 | `PlayerViewModel` 已有带进度和请求头的顺序备用线路切换及历史保存 | 参考错误分类、有限重试和面板恢复流程；无需重复实现已经存在的备用线路链路 |

本地证据入口：[源实现](../../source/tvbox/src/main/kotlin/com/flytech/juying/source/tvbox/TvboxSource.kt)、[Repository](../../core/data/src/main/kotlin/com/flytech/juying/core/data/DefaultRepositories.kt)、[搜索界面](../../feature/search/src/main/kotlin/com/flytech/juying/feature/search/SearchFragment.kt)、[播放器 ViewModel](../../feature/player/src/main/kotlin/com/flytech/juying/feature/player/PlayerViewModel.kt)。

## 验证边界

- 已读取上述固定提交源码，并确认仓库与正式发布状态；“有实现”不代表本次实机验证通过。
- 未安装或运行 LibreTV，未执行其测试，未验证第三方源、长时间播放、设备解码或远程服务安全性。
- 本轮仅新增本评估记录，没有修改聚映 Android 业务代码、V2 设计、依赖或暂存区。
