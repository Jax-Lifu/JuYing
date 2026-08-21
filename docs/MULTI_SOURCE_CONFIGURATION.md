# 多源可配置机制

聚映参考 TVBox 的“来源清单可配置”体验，但不兼容 TVBox 配置协议：应用只加载随制品发布、可审查的声明式 JSON，并只实例化已内建的来源适配器。不会请求、下载或执行远程 JSON、JAR、JS、Python、解析服务、代理或网盘凭据。

## 配置位置与格式

运行时默认清单是 `apps/juying_app/assets/config/sources.json`；Schema 和可复制模板在 `configs/sources.schema.json`、`configs/sources.example.json`。每个条目必须声明：稳定 `id`、显示名称、来源类型、`adapter`、官方入口、启用状态、授权状态与能力集合。

当前注册的内建适配器：

| adapter | 允许的来源 | 说明 |
|---|---|---|
| `cctvOfficial` | `cctv-official` | 仅 CCTV 官网既有适配器；不能改写官方入口、授权类型或未实现能力。 |

运行时还支持用户添加 `M3uPlaylistAdapter`。它借鉴 TVBox 客户端的 M3U 直播清单体验，但有以下固定边界：

- 只能通过媒体库添加 HTTPS 清单，地址不能含账号、查询参数或片段；
- 添加前必须明确确认自己拥有访问和播放权利；
- 只解析 `#EXTM3U` / `#EXTINF` 声明和下一行 HTTPS 媒体地址；
- 不接收自定义请求头、Cookie、代理、解析服务、脚本或插件；
- 清单最大 2 MiB、最多 2000 个频道、单次请求超时 10 秒；
- 频道统一映射为“直播”，保存的只有清单元数据和权利确认时间，具体播放 URL 只存在于播放会话。

M3U 来源与内建来源使用同一个 `MediaSourceRegistry`，因此设置页启停、联邦搜索、儿童过滤、来源健康、熔断、选集和播放器都走同一流程。

新增来源不是在 JSON 中填写网页或播放规则：先实现并审计 `MediaSourceAdapter`，在 `MediaSourceAdapterFactory` 注册固定键，再允许 Schema 和清单引用它。适配器输出仍要经过 `ValidatedMediaSourceAdapter` 与 `ManagedMediaSourceAdapter`，并遵守统一 ID、分类、策略、健康与熔断约束。

## 用户控制与验证

设置页使用同一来源注册表展示并持久化用户启用/停用选择；联邦搜索只查询已启用、已授权、声明搜索能力且未熔断的来源。配置错误会回退到内置最小 CCTV 官方清单，不会改用第三方 URL。

每个新增适配器至少需要补充配置解析测试、工厂白名单测试、统一契约测试，以及单源/全部来源/失败隔离验证。第二来源仍受 `FOUNDATION_PLAN.md` 的 P0 和 ADR 门禁约束。
