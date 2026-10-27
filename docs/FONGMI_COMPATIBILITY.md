# FongMi/TV 兼容性对照

审查日期：2026-10-26。上游固定为 [FongMi/TV aa30eb047c749fe5a96dd47b94947cda2421354f](https://github.com/FongMi/TV/commit/aa30eb047c749fe5a96dd47b94947cda2421354f)，提交日期 2026-10-25。本文记录修复前的 JuYing 差异，后续实现是否通过以测试结果为准。

## 结论

本轮已完成：图片/Base64 与 2423 解码、重定向后的相对路径、中文域名表单、XML CMS、可选 Init 与真实 Application 上下文、safeDns/SpiderDebug 宿主签名、Gson 依赖及 R8 保留规则。肥猫金牌与急救在 Cayin 的原生解码抽测通过，详见 [候选审查](TVBOX_PRESET_AUDIT.md)。下文保留修复前差异作为对照；多层仓库、drpy 扩展、代理和通用嗅探仍未完成。

应优先补通用 TVBox 协议兼容，不能将图片包装、AES 包装或运行时依赖缺失直接认定成坏源。FongMi 的实现包括配置解码、路径处理、宿主 ABI、JS 模块和播放结果解析，并非只有 Spider 基类。原生 View / Media3 UI 无需随之替换。

## 配置与路径

| 边界 | FongMi 行为 | JuYing 修复前缺口 |
| --- | --- | --- |
| Base64 包装 | 在内容中查找八位字母数字后跟两个星号，解码其后全部数据；容器可以是图片字节经字符串读取后的内容 | 直接 JSON parse，因此饭太硬 JPEG 包装失败 |
| CBC 包装 | 识别 `2423`，去空白后转 hex；从解码文本取内嵌 key 和末尾 13 字符 IV，补 ASCII 0 至 16 位；AES/CBC/PKCS5Padding | XC 配置无法解析 |
| 相对地址 | Decoder 使用 HTTP 重定向后的地址作为基准，处理 `./` 与 `../`，特意保护 JS URL 查询中的相对参数 | api/jar 有局部解析，但 ext 原样传递；重定向后 base URL 仍旧 |
| 多仓 | VodConfig 识别 `urls`，选择第一项后递归加载 | 当前仅一层；须检测循环和深度上限 |
| storeHouse | 固定版本 VodConfig 未见 `storeHouse/sourceUrl` 支持 | 不应宣称此格式已由 FongMi 提供；如兼容需单独定义 |
| 中文域名 | 上游网络层使用 OkHttp HttpUrl | SettingsViewModel 的 java.net.URI.host 会拒绝 Unicode 中文域名，应使用支持 IDN 的 HTTP 解析器 |

依据：[Decoder.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/utils/Decoder.java#L25)、[Crypto.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/utils/Crypto.java#L82)、[VodConfig.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/api/config/VodConfig.java#L141)。

CBC 细节：hex 解码文本先转小写；key 位于 `$#` 与 `#$` 之间；ciphertext 位于原 hex 首个 `2324` 之后，去掉末尾 26 hex 字符；IV 是末 13 文本字符。协议中的补位是字符 `0`，不是零字节。新增实现仍需对 hex、分隔符、key/IV 长度、输出大小和解析失败作边界测试。

## JAR 宿主

FongMi 在创建站点实例之前调用可选的 `com.github.catvod.spider.Init.init(Context)`，注册可选 `Proxy.proxy(Map)`，并使用兼容的父 ClassLoader。站点初始化还设置 `siteKey`、`net`、`local`。JuYing 修复前只创建 Spider 并调用实例 init，不能代表真实生态 JAR 已兼容。[JarLoader.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/api/loader/JarLoader.java#L113)、[Spider.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/crawler/Spider.java#L25)。

对三份用户配置引用的 JAR 仅做 ZIP/DEX 静态检查：

| JAR | 静态观察 | 结论边界 |
| --- | --- | --- |
| 肥猫 | 配置 MD5 匹配；引用宿主 `Spider.safeDns(): okhttp3.Dns`、`SpiderDebug.log(String)`、`log(Throwable)`；带 Init | 当前宿主缺这些方法/类；debug MainActivity 引用不代表正常路径会执行 |
| 摸鱼儿 | 配置 MD5 匹配；引用 SpiderDebug；包含 FishGuard 的 armv7/arm64 so | 补宿主接口不能证明加固代码可运行 |
| 短剧 | 无配置 MD5；引用旧 `Spider.initApi(SpiderApi)`、SpiderApi 与大量未随包定义的 xbpq 类型 | 当前固定版 FongMi Spider 也无此旧接口；不能靠无行为 stub 宣称兼容 |

精确引用签名在临时证据 `build/tvbox-audit/dex-hosts.json`；检查脚本为 `build/fongmi-reference/inspect_dex.py`。该静态审查阶段没有执行 JAR；后续肥猫实机结果另记。方法引用证明链接需求，不能证明实际调用路径、安全性或完整功能。MD5 只核对配置声明与下载内容一致，不证明发布者可信。

已证实且最小的宿主 ABI 是 `public static Dns safeDns()` 与 `public static void SpiderDebug.log(String/Throwable)`。上游 safeDns 委托 OkDns；没有 DoH/hosts 配置时，OkDns.lookup 最终就是 Dns.SYSTEM。现有项目可保留系统 DNS 并实现相同签名，不必新增 DNS 依赖。第三方 log 可能含凭据，保留 ABI 时抑制正文或仅记录异常类，不能照搬上游明文日志。[SpiderDebug.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/crawler/SpiderDebug.java)、[OkDns.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/net/OkDns.java)。

不要整拷上游 OkHttp 网络工厂：固定版本包含恒真的 hostnameVerifier 和 trustAllCertificates。移植协议所需行为时继续保留本工程的 TLS 验证。[OkHttp.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/net/OkHttp.java#L213)。

## JavaScript

### 上游可直接参考的调用约定

FongMi 以模块形式加载并支持三种输出：

1. 模块设置的 `globalThis.__JS_SPIDER__`；
2. 命名导出的工厂 `__jsEvalReturn()`；
3. default 对象，或接收 `{type: 3, key: siteKey}` 的 default 工厂。

legacy init 接收 `{skey, stype, ext}`；ext 若本身为 JSON 对象会解析成对象。detail 的 Java 列表在 JS 侧转换为首个 ID。JuYing 修复前通过文本包含判断 legacy，以普通 script 执行且直接赋工厂、不调用工厂；这与真实 ESM legacy 不兼容。[spider.js](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/assets/js/lib/spider.js)、[QuickJS Spider](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/java/com/fongmi/quickjs/crawler/Spider.java#L281)。

### 模块与资产

FongMi Module 支持普通 HTTP 模块、`assets://js/lib/...` 和 `lib/...`。资产由受控 runtime 声明清单读取，不是任意文件读取。[Module.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/java/com/fongmi/quickjs/utils/Module.java#L119)、[RuntimeModule.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/utils/RuntimeModule.java#L194)。

| 上游资产 | 字节数 | 导出/依赖 |
| --- | ---: | --- |
| `cheerio.min.js` | 356592 | default + load/html/text/xml/jp/jpo/jinja2 等；无外部静态 import |
| `crypto-js.js` | 198120 | 写入 globalThis.CryptoJS；无外部 import；需要随机数的功能仍需安全随机 API |
| `cat.js` | 486451 | 命名导出 Crypto、Uri、lodash、dayjs、cheerio、JSONPath 等；较大，按实际依赖引入 |
| `gbk.js` | 56203 | 按编码需求引入 |
| `net.js` | 17164 | 网络宿主包装，并创建 global/window/self 别名；依赖宿主绑定 |
| `spider.js` | 3012 | 输出形态与调用包装 |
| `similarity.js` | 2264 | 按实际依赖引入 |
| `ui.js` | 1209 | 依赖宿主 UI 绑定 |

资产来源：[上游 js/lib](https://github.com/FongMi/TV/tree/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/assets/js/lib)。其中 cheerio、crypto-js、net、spider 已保存到 `build/fongmi-reference/quickjs/src/main/assets/js/lib/` 供实现核对，未加入应用。

FongMi 对 `https://down.nigx.cn/qu.ax/*.js` **没有别名替换或内置回退**。其 Module.read 对 HTTP 执行正常 Net 请求。gao 的当前 drpy2.min.js 引用五个该域名文件，主机探测均为 403；只补 assets 不会使该依赖链恢复。不能据此声称同一时刻 FongMi 真机必然失败或成功，因为网络、全局请求头和缓存尚未对比。

### 宿主桥边界

FongMi Global 额外绑定网络、缓存、HTML 查询、URL、散列/加密、代理、Cookie、Web/UI 等方法，部分 JS 可通过 JAR 中 `com.github.catvod.js.Function(QuickJSContext)` 扩展。JuYing 当前只有 req/fetch/console/page，不足以泛称“全量 drpy 兼容”。优先按实际站点触发的方法实现真实行为；不要用空 stub 掩盖缺失能力。[Global.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/java/com/fongmi/quickjs/method/Global.java#L164)、[createFun](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/quickjs/src/main/java/com/fongmi/quickjs/crawler/Spider.java#L270)。

补充真实脚本证据：饭太硬解码配置中的 drpy2.min.js 使用同仓 node-rsa/pako/模板/gbk/json5/jinja 六个模块，没有 gao 的 down.nigx.cn 导入；原配置代理请求超时、直接 GitHub 请求可读，尚未运行。该脚本模块顶层引用 pdfh/pdfa/pd，并使用 joinUrl 和 local 的旧 namespace,key 双参数形式。最新 FongMi 的 Global 不直接绑定这些 HTML helper，且 net.js 的 local 是单 key API；兼容此旧脚本仍需核对其 JAR Function 注入，不能只替换新版 net.js。原始文件位于 `build/tvbox-audit/fanfan-drpy-direct.body`。

## CMS 与播放

- type 0 分类/详情使用 `ac=videolist`；type 1 使用 `ac=detail`。home 不需要 ac。
- search 使用 wd、quick，后续页传 pg；返回可能只有基础字段，上游按 ID 补一次详情获取图片。
- XML 形态为 rss/class/ty(id) 与 rss/list/video；详情播放为 video/dl/dd(flag)，文本仍为集名、地址的 TVBox 分隔格式。
- type 0/1 的 episode URL 是直接播放输入，不再请求 player API；网页识别或 site.playUrl 才进入解析流程。
- type 4 home 传 filter=true；category 额外把筛选对象 URL-safe Base64 放 ext；通用 extend 保持字符串语义（不能把 JsonPrimitive.toString 的引号额外传上游）。

依据：[SiteApi.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/api/SiteApi.java#L53)、[Result.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/bean/Result.java#L39)、[Vod.java](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/app/src/main/java/com/fongmi/android/tv/bean/Vod.java#L33)。

## 肥猫 JAR 的外部依赖补查

父任务在真机完成 Application 上下文与 Init 修复后仍遇到 ClassNotFoundException，因此补查该 JAR 的全部 DEX 类型表。39 个配置中的 csp_ 站点类都在包内，JS 站点另算。缺失类型是对“JAR 自身定义”而言，尚需与最终 APK 合并类表及实际异常类名核对。

| 外部类型包 | 静态证据 | 固定上游依赖/处理建议 |
| --- | --- | --- |
| com.google.gson | Gson、GsonBuilder、JsonElement、JsonObject、JsonParser、SerializedName、TypeToken | 首先补 `com.google.code.gson:gson:2.14.0`；上游 catvod 直接 api 依赖 |
| org.jsoup | 没有外部类型引用 | 本次肥猫 JAR 没有证据要求新增 Jsoup，避免预先添加 |
| com.google.zxing | BarcodeFormat、EncodeHintType、MultiFormatWriter、BitMatrix | 上游 `com.google.zxing:core:3.5.4`；二维码路径需要时补，不能由静态引用推断分类失败原因 |
| com.whl.quickjs.android / wrapper | QuickJSLoader、Console、JSCallFunction、JSMethod、JSObject、QuickJSContext | 旧 QuickJS Java ABI；现有 dokar3 依赖不提供这些包名，需要运行路径触发后另行对照，不能靠加新版 QuickJS 坐标解决 |
| org.slf4j | ILoggerFactory、impl.StaticLoggerBinder | 先核对最终 APK 已有 SMBJ 的传递依赖；不为此直接添加重复日志实现 |
| okhttp3、org.xmlpull.v1 | 网络与 Android XML 接口 | 当前工程已有；继续保留现有 OkHttp/TLS，不全量跟随上游网络依赖升级 |

版本依据：[固定提交 libs.versions.toml](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/gradle/libs.versions.toml)、[catvod/build.gradle](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/build.gradle)。这里给出的是有上游证据的依赖版本，不声称是所有历史版本中的最低可用版本。临时证据 `build/tvbox-audit/dex-hosts.json` 的 `external_types` 和 `defined_classes` 保留完整结果。

## 建议验证顺序

1. 固定 fixture：JSON/BOM/注释、JPEG+Base64、CBC、无效 hex/标记/长度；重定向后相对 ext、JS query 保留、多仓循环。
2. 固定 runtime fixture：optional Init 成功/缺失/失败；三种 JS export；assets 模块、未知资产拒绝、取消和内存上限。
3. 固定 CMS fixture：XML/JSON 的 home、category、search、detail、直链播放；XML 外部实体关闭。
4. 真实配置：导入与子站列表成功后，再检查分类/搜索/详情/媒体解析；最终用同一 APK 真机播放验证。

上述顺序不把配置成功当成播放通过，也不为未知远程代码的安全性背书。上游 [LICENSE.md](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/LICENSE.md) 声明 GPL-3.0；移植代码和资产时保留其来源、版本及相关第三方许可。当前研究只保存文档和临时参考文件，没有改动应用源码。

