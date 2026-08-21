# TVBox 生态调研与聚映来源接入报告

调研日期：2026-08-19  
范围：[`qist/tvbox`](https://github.com/qist/tvbox) 仓库、其 README 列出的客户端与配置入口，以及 FongMi/TV、TVBoxOS、Box、Selene-Source、Animeko、Kazumi 的公开实现。本文是**来源准入研究资料**，不是第三方配置导入说明，也不构成内容或播放授权。

## 结论先行

`qist/tvbox` 是面向 TVBox/OK影视/猫影视客户端的配置集合，而非稳定、可授权的媒体服务或统一 API。它的核心价值是帮助理解一个来源生态常见的目录、直播、搜索、解析和扩展脚本形态；它不能作为聚映的聚合来源，更不能将 README 中的 JSON、TXT、JAR、JS/PY 规则、代理地址或网盘 token 直接接入。

聚映应只把此生态当作“候选来源线索库”：从每一条线索反查权利方官网或书面授权，再以一个受版本控制的 `SourceAdapter` 对接。未满足授权、地区、儿童、设备和原生播放条件的候选，必须停在 `officialFallback`，不能出现在自动搜索、推荐、历史或播放候选中。

## 仓库观察

仓库 README 自述包含 TVBox 配置、直播列表、JSON/TXT/M3U、JAR 与 JS/PY 目录；仓库页面列出的顶层目录也可见 `cat`、`jar`、`js`、`live`、`py` 等。README 明确表示内容仅供学习测试、有效性不作保证，并指出配置来自第三方分享；这不能替代内容权利、接口许可或安全审计。仓库根目录未见许可证声明，公开可见不等于可复制或分发。[仓库首页](https://github.com/qist/tvbox)｜[README 原文](https://raw.githubusercontent.com/qist/tvbox/master/README.md)

这与聚映架构存在本质差异：TVBox 配置通常把站点规则、解析器、播放地址、扩展执行环境和客户端行为揉在同一份可变配置中；聚映必须在适配器边界完成标准化，统一层只接收媒体条目、季/集、搜索命中和短生命周期的已授权播放描述。

| TVBox 配置常见元素 | 在聚映中的正确归位 | 处理原则 |
|---|---|---|
| `sites` / 分类 / 搜索规则 | 来源适配器 | 输出固定八类与统一搜索命中，保留原标签仅作诊断。 |
| 直播线路、点播 URL、解析规则 | 播放候选解析（适配器内部） | 仅接受有授权、可验证的原生播放描述；不可用时回退官方页。 |
| JAR、JS、PY 扩展 | 不纳入运行时 | 不下载或执行不受信任代码；如需能力，重写为受审计的原生适配器。 |
| 网盘 token / OpenToken | 安全存储引用 | 不导入、不共享、不记录；还需单独确认该网盘及内容的许可。 |
| GitHub/代理/Cloudflare 配置分发地址 | 不作为媒体来源 | 仅可用于研究取证；不得把代理当作来源授权或可信边界。 |

例如可见配置的顶层包括 `spider`、`lives`、`sites`、`parses`、`flags`、`doh` 与 `rules`；其中 `sites` 的 `api`/`ext` 可指向 JAR、脚本、站点或不透明参数，`parses` 和 `rules` 可绑定解析服务、伪装请求头或媒体清单重写。这些字段由不同客户端解释，类型并不稳定，不能作为聚映契约或迁移格式。[示例配置](https://raw.githubusercontent.com/qist/tvbox/master/0821.json)

## README 推荐客户端：仅作交互研究

README 提及的客户端各自强调直播多线路、回放、投屏、弹幕、竖屏或多平台等能力。它们可用于比较 TV 焦点、直播选源和移动布局，不能因此继承其中配置、接口或内容可用性。

| README 条目 | 链接 | 可研究的产品能力 | 聚映边界 |
|---|---|---|---|
| FongMi / OK影视 | [FongMi/TV](https://github.com/FongMi/TV) | 多直播线路、自动换源、直播倍速、投屏 | 选源必须保留来源版本；自动切换不能跨越授权/地区/内容身份。 |
| q215613905 / TVBoxOS | [TVBoxOS](https://github.com/q215613905/TVBoxOS) | 直播回放交互 | 回放仅在来源和设备显式声明时显示。 |
| takagen99 / Box | [Box](https://github.com/takagen99/Box) | 回放及 TV 界面信息架构 | 仅研究交互，不复制规则或资源配置。 |
| 皮皮虾发布频道 | [Telegram](https://t.me/pipixiawerun) | 回放、弹幕的产品呈现 | 发布频道不是供应商 API；弹幕还需独立合规与隐私评估。 |
| CatVodOpen | [catvod/CatVodOpen](https://github.com/catvod/CatVodOpen) | 多平台与配置载入体验 | 不导入私有仓库 token、DAV 凭据或可执行扩展。 |
| TVBoxOS-Mobile | [XiaoRanLiu3119/TVBoxOS-Mobile](https://github.com/XiaoRanLiu3119/TVBoxOS-Mobile) | 竖屏移动端布局 | Flutter 共享状态，移动仅是输入与窗口适配。 |
| TVBoxOSC | [o0HalfLife0o/TVBoxOSC](https://github.com/o0HalfLife0o/TVBoxOSC) | 构建/发布链路线索 | 仅审查开源构建，不信任第三方编译 APK。 |

许可证与维护状态同样是边界：FongMi/TV 为 GPL-3.0；TVBoxOS、Box 和 TVBoxOS-Mobile 为 AGPL-3.0，后者已归档；TVBoxOSC 当前重定向至 [j4Uq/TVBoxOSC](https://github.com/j4Uq/TVBoxOSC)，未见明确许可证。即使只研究代码，也应先记录版本、上游提交和许可证；任何复制、派生或链接依赖均须经许可证审查。

## 六个实现仓库的可借鉴边界

以下结论基于 2026-08-19/20 对公开主分支及其 README、许可证和配置/播放相关代码的静态审查；未运行第三方 APK、未执行任何规则，也没有把其来源加入聚映。

| 项目 | 静态结论 | 可复用的工程经验 | 聚映明确不采纳 |
|---|---|---|---|
| [FongMi/TV](https://github.com/FongMi/TV) | GPL-3.0 Android 客户端；支持多来源并发搜索、播放器状态和线路恢复，也支持远程爬虫/嗅探。 | 请求 epoch 防止旧结果覆盖、来源级状态、最后一次有效配置缓存、同一来源内的受限恢复。 | JAR/QuickJS/Python、Dex 动态加载、网页嗅探、代理/DoH/hosts、伪装请求头，以及跨来源静默换源。 |
| [q215613905/TVBoxOS](https://github.com/q215613905/TVBoxOS) | AGPL-3.0；以 JSON 的 `sites/parses/lives/hosts/DoH` 描述客户端与来源行为。 | 把搜索、筛选、直播/回放、播放器能力显式建模。 | 让原始配置字段、解析器、hosts 覆盖和远程插件穿透领域模型或播放器。 |
| [takagen99/Box](https://github.com/takagen99/Box) | AGPL-3.0 的实验性 TVBox 分支，维护时效不稳定。 | TV/Google TV 焦点、画中画及播放器布局只能作为交互参考。 | 复制代码、依赖其发布包或假定其配置具授权/稳定性。 |
| [MoonTechLab/Selene-Source](https://github.com/MoonTechLab/Selene-Source) | 未发现许可证；订阅可解码为任意 CMS API/M3U，且缺少签名、允许域名、授权和 schema 门禁。 | 并发查询、来源错误隔离、M3U/EPG 的受限解析、健康检查应有资源上限。 | 任意 API、HTML 正则抽取 m3u8、拼接代理、内网/HTTP 探测、下载媒体分片测速。 |
| [open-ani/animeko](https://github.com/open-ani/animeko) | AGPL-3.0；将作品身份与可播放候选分层，并有来源会话、缓存隔离和失败状态概念。 | 统一内容身份与来源版本分离、请求取消/旧结果抑制、版本化事务配置、来源优先级。 | 其实际规则、BT/磁力、Cookie/验证码/WebView 捕获、iframe 和防盗链绕过。 |
| [Predidit/Kazumi](https://github.com/Predidit/Kazumi) | GPL-3.0；关联规则仓库采用 MIT，但来源规则仍独立受授权与安全约束。 | 强类型来源契约、操作级空/超时/失败状态、播放候选与持久元数据分离。 | 导入规则订阅、远程可执行配置、持久化播放 URL 或复制 GPL 代码。 |

这些经验已映射到聚映实现：来源配置新增受控 `configVersion` 与 `priority`；联邦搜索区分 `empty`、`failed`、`timedOut` 与 `skipped`，并仅在“精确标题、可播放性”之后以来源优先级稳定排序。其目的是可解释展示，不会替换用户实际选择的来源版本。

播放层只接受适配器给出的统一 `PlaybackDescriptor`。目前唯一允许用户扩展的直播入口是**用户确认拥有权利的 HTTPS M3U**：读取上限为 2 MiB、频道上限为 2,000、请求超时 10 秒；清单和媒体 URL 都拒绝 HTTP、用户信息、脚本、请求头/Cookie 配置与播放器侧解析。第三方配置候选均永久没有播放准入资格。

在“设置 → 内容来源”中可手动添加 M3U 直播来源。提交后应用会自动检测 `#EXTM3U` 结构、频道上限和每条 HTTPS 流；全部通过才注册、持久化并加入统一目录/搜索/选集/原生播放。已通过的清单会在下次启动时自动恢复；检测失败、授权未确认或不符合 URL 规则时不会新增来源。

## “各路大佬配置”链接的准入判定

README 罗列了饭太硬、okjack、王二小放牛娃、摸鱼儿、霜辉月明、 小米小爆脾气、南风、神器、巧技、Ray、俊于、橘子柚及本仓库衍生配置等入口；其中既有裸 HTTP、IDN 域名、非标准端口、raw 文件、动态短路径，也有聚合配置与代理入口。[完整清单](https://raw.githubusercontent.com/qist/tvbox/master/README.md#L69-L101)

这些链接的共同属性是**第三方配置分发点，不是已授权内容源**。它们适合用作“可能存在某个官网来源/数据格式”的线索；在未逐项完成权属、条款、地区、接口稳定性和安全审计前，聚映一律不能把它们作为 `SourceAdapter` 的上游，也不应在应用内展示、预置或从中同步 URL。

特别排除以下内容：

- 任何聚合点播、直播或“解析”条目：可能无权再分发内容或绕开受保护播放链路。
- 任意 JAR、JS、PY、Node/QuickJS 脚本：可执行供应链，不能在客户端动态加载。
- HTTP 明文入口、端口服务、域名代理和 raw 配置镜像：无来源身份、传输或内容完整性保证。
- 网盘授权、token、转存和并发调优说明：会引入账户滥用、凭据泄露与服务条款风险；README 本身也提示并发或异地使用可能导致限制/封禁。[相关说明](https://raw.githubusercontent.com/qist/tvbox/master/README.md#L103-L114)

## 用户补充资源目录审计

已静态审计用户提供的 `C:\Users\Administrator\Downloads\resources.json`（文件内声明版本 1、更新时间 2026-08-17）。它有 94 条条目：`online_video` 34 条、`tvbox_config` 15 条、`magnet_search` 12 条、播放器 7 条及其他工具/开源项目；其中 65 条的自身元数据已标记为 `copyright: high`。其余项目大多仍为 `unknown` 或 `medium`，且记录的 `caution`/推荐星级并不是权利方授权、接口许可或播放许可。

目录中 15 个 `tvbox_config` 条目与用户最初提供的 14 个配置地址重合，并额外包含“小盒子”主页；现已全部登记为应用内**隔离检测候选**。它们不属于 `SourceAdapter`，结果对象的 `allowedForPlayback` 恒为 `false`。

因此该目录被采纳为**补充候选线索**，而不是聚映播放来源：

- `online_video`、`tvbox_config`、`magnet_search`、云盘搜索和第三方播放器：不进入目录、联邦搜索、推荐、历史或播放器。
- Animeko、Kazumi、Selene 和 FongMi 等项目条目：并入上述开源生态调研，不能借由目录中“推荐”标签获得依赖或来源准入。
- 字幕、IPTV、开源工具等低风险但权限未知的条目：只有在对方的官方条款、地区/儿童策略及接口许可被逐项记录后，才可新建受审计适配器；当前状态仍为 `unknown`。

这项处理确保“补充”不会把资源索引的主观评分误当作版权、供应链或播放授权，也不会将 URL、Cookie、token 或规则导入到播放器。

## 面向“其他源”的落地流程

```text
TVBox 配置线索（只读研究）
  → 识别实际权利方 / 官方详情页
  → 授权、条款、地区、年龄、设备、隐私与接口许可核验
  → 来源注册表（状态、能力、健康、关闭开关）
  → 受审计的单一 SourceAdapter
  → 策略引擎
  → 统一目录 / 联邦搜索 / 详情选集 / 原生播放或官方回退
```

每个拟接来源的最小准入包：

1. **权利与入口证据**：权利方、官方详情 URL、允许的接入方式、地区/终端/年龄限制与复审日期；无法确认时状态为 `unknown`，不参与聚合。
2. **能力声明**：只声明实际支持的 `browse`、`search`、`episodes`、`playAuthorizedMedia` / `nativePublicPlayback`、`officialFallback` 等能力；未知即禁用。
3. **身份与映射**：使用 `sourceId:sourceItemId`、来源版本和季/集键；类别映射到八个统一分类，原始分类仅进入受控诊断字段。
4. **播放边界**：播放器只收取会话内、已授权、可过期的 URI；绝不在播放器侧解析网页、拼 URL、执行规则或持久化 URL/token。
5. **隔离与测试**：录制脱敏夹具覆盖目录、搜索、详情、选集、原生播放可用/受限、超时和下架；单源失败不得破坏全部来源。

## 当前建议的下一步

在编写第二个适配器前，先按 `docs/FOUNDATION_PLAN.md` 完成 P0 的身份、元数据权威、来源生命周期、数据归属、策略引擎和契约测试 ADR。随后选择**一个具有明确官方授权和稳定官网回退**的候选，先实施只读 `browse + officialFallback`，在获得原生播放许可后才新增播放能力。Windows 是本项目唯一已承诺的验证平台；其它平台需另行验证。

已落地的 TVBox 生态借鉴项：用户可添加经过权利确认的 HTTPS M3U 直播清单；它被转换为统一来源、直播条目、单集和播放描述，不执行 TVBox 私有规则。README 列出的第三方聚合配置仍未预置或导入。

## 参考资料

- [qist/tvbox 仓库](https://github.com/qist/tvbox)
- [qist/tvbox README（配置、客户端与链接清单）](https://raw.githubusercontent.com/qist/tvbox/master/README.md)
- [聚映统一媒体契约](UNIFIED_MEDIA_CONTRACT.md)
- [聚映防返工基础规划](FOUNDATION_PLAN.md)
- [聚映内容与合规边界](COMPLIANCE.md)
