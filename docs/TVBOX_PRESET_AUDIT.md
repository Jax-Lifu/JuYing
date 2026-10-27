# TVBox 预置候选审查

审查时间：2026-10-26（Asia/Shanghai）。范围为用户提供的 10 个入口。先在 Windows 检查配置与依赖，再在 Cayin（Android 14，Ethernet）执行选定站点的分类、详情、解析与原生播放。下表中的其他入口仍以主机静态检查为限。

## 结论

已参照 [FongMi/TV](https://github.com/FongMi/TV) 补齐图片/Base64 与 2423 加密配置、重定向相对路径、中文域名、XML CMS 和部分 JAR 宿主契约，并执行了选定第三方 JAR。按用户要求预置肥猫中的两个独立站点；没有预置整个仓库。多层仓库选择和完整 drpy 宿主仍未实现。

- **金牌（`csp_Jpys`）**：4 个分类，按抽测影片标题搜索返回 8 项，详情及分集解析通过；Media3 + SurfaceView 实际播放 1920×808，进度超过 2 秒。
- **急救（`csp_FirstAid`）**：8 个分类，详情及分集解析通过；实际播放 1280×720，进度超过 2 秒。它是急救教学内容，配置明确声明不支持搜索，因此不参与搜索。
- 两个预置来源均可编辑、停用、删除；删除后不自动恢复。以 `extra.siteKey` 限定站点，不带入同仓网盘、配置中心与其他未验证站点。
- 兔小贝只通过主机媒体字节检查，drpy 依赖仍未闭合；XYQ 柚子资源抽测媒体 403；其他站点不因此获得可播放结论。

设备运行证据：`build/tvbox-audit/device-feimao-delivery.log`。该用例通过实际数据源和播放器验证两个站点，不等同于完整 UI 或长时播放验收；最终包及页面回归记录见 [验证边界](TVBOX_CCTV.md#验证边界)。

## 入口检查

| 用户入口 | 本次返回 | 配置与运行时观察 | 当前建议 |
|---|---|---|---|
| [饭太硬](http://www.饭太硬.net/tv) | 200，20,063 字节；响应类型 image/x-ms-bmp，文件头实际为 JPEG/JFIF | 按 FongMi 标记后 Base64 解出 49 个 type3 站点（46 个 csp_、3 个 drpy JS）；JAR 使用 JPG 地址并声明 MD5 | 配置解包通过；待 JAR/站点播放验证 |
| [肥猫](http://肥猫.net/) | 200，17,857 字节；响应类型 text/html，但正文为 JSON | 40 站；39 个 csp_ JAR 站点，另一个 API 路径含 JS；有配置中心、网盘、P2P、影视混合。全局 JAR 托管在图片 URL，声明 MD5 | 金牌、急救通过设备原生播放抽测并单站预置；其余未全部验证 |
| [摸鱼儿](http://我不是.摸鱼儿.top) | 200，33,081 字节 JSON | 99 站；主要为 JAR，涵盖网盘、影视、音乐、少儿；全局 JAR 来自上传文件地址并声明 MD5 | 待验证；网盘站继续跳过 |
| [王二小](http://tvbox.王二小放牛娃.top) | 200，跳转至 moji.com 的 JPG URL，正文实际为 JSON | 63 站，全部 csp_ JAR；配置中心与网盘类置前，存在 P2P；全局 JAR 也使用 JPG URL并声明 MD5 | 待验证；不能用首站是否有影片判断整仓质量 |
| [kstore one.json](https://9877.kstore.space/one.json) | 404 | 当前入口没有取得配置 | 本轮不选；可稍后复测 |
| [XC](https://gh-proxy.com/raw.githubusercontent.com/yoursmile66/TVBox/refs/heads/main/XC.json) | 200，64,681 字节；以 `24233234382324` 开头的文本 | 按 FongMi AES-CBC 解出 88 个 type3 站点（87 个 csp_、1 个 drpy JS）；文件近期有更新 | 配置解码通过；待 JAR/站点播放验证 |
| [gao js.json](https://gh-proxy.com/https://raw.githubusercontent.com/gaotianliuyun/gao/master/js.json) | 200，51,621 字节 JSON | 298 站；227 个 JS 路径、71 个 csp_ 站点。JS 多数复用 drpy2；配置文件最近提交为 2024-10-10，不能据此推断每个站点仍可用 | 优先只验证兔小贝；不能整仓默认搜索 |
| [XYQ](https://gh-proxy.com/https://raw.githubusercontent.com/xyq254245/xyqonlinerule/main/XYQTVBox.json) | 200，24,820 字节；含整行 `//` 注释 | 清理注释后 48 站；39 个 JAR、8 个 JS、1 个 CMS XML。现有 clean() 可处理整行注释 | 单站复核；其 CMS 抽测媒体 403，不能当可播放预置 |
| [短剧频道](http://box.ufuzi.com/tv/qq/短剧频道/api.json) | 200，26,950 字节 JSON | 35 站全部 `csp_XBPQ`；全局 `./spider.jar` 无 MD5 声明；大量外部 HTML 提取规则 | 待 JAR/规则与实际播放验证；站名不能证明内容质量 |
| [无邪 wx.json](https://gh-proxy.com/https://raw.githubusercontent.com/wxrjck/-YSC-/refs/heads/main/wx.json) | 200，414 字节 JSON | 顶层为 `storeHouse`，子项使用 `sourceName/sourceUrl`；其中 yx.txt 可读取，是 `urls` 二层仓库，首项又指向饭太硬。另有更新时间说明项，不是 URL | 需要多层仓库解析与无效说明项过滤；不作为独立内容站重复预置 |

原始返回及 SHA-256：`build/tvbox-audit/fetch.json`。文件正文只保存在忽略的 build 目录，用于本地复核；报告不把外部配置全文复制进应用。

## FongMi 格式复核与 JAR 静态下载

参考固定版本 [Decoder.java（aa30eb0）](https://github.com/FongMi/TV/blob/aa30eb047c749fe5a96dd47b94947cda2421354f/catvod/src/main/java/com/github/catvod/utils/Decoder.java) 中的 Base64 标记提取和 `2423` CBC 数据算法，在主机上仅解码数据，没有加载爬虫代码：

- 饭太硬解码后的 JSON 为 13,238 字节，SHA-256 `720bb98818863a36dcc99463db88fa5578460122a461e716270166a174e4249a`。
- XC 解码后的 JSON 为 32,314 字节，SHA-256 `5306027c1adf7bf0af029f94f2bfe490b838e2121b116ebc861dee60f6aa3d27`。
- 原始输入、解码结果与统计见 `build/tvbox-audit/{fantaiying,xc}.decoded.json`、`decoded-summary.json`。它们可作为应用兼容实现的真实输入对照，不能替代应用内回归测试。

初次静态检查下载、读取 ZIP 目录的 JAR（肥猫后来追加了设备执行）：

| 配置 | 下载结果 | 静态观察 |
|---|---|---|
| 肥猫 | 1,048,712 字节；MD5 与配置声明一致 | 标准 ZIP，含 `classes.dex`，未见 ZIP 内 `.so` |
| 摸鱼儿 | 2,695,646 字节；MD5 与配置声明一致 | 含 `classes.dex` 及 `assets/FishGuard-v7.so` / `FishGuard-v8.so`，需要额外验证原生依赖 |
| 短剧频道 | 635,660 字节；配置未声明 MD5 | 标准 ZIP，含 `classes.dex`，未见 ZIP 内 `.so` |

证据：`build/tvbox-audit/jars.json`。MD5 相符仅说明下载字节与配置一致，未证明发布者身份或运行安全。肥猫选定站点已执行；摸鱼儿的原生依赖及短剧规则尚未完成播放验收。

## 单站验证：兔小贝

配置来源：[gao/js.json](https://github.com/gaotianliuyun/gao/blob/master/js.json)。

- `key`: `drpy_js_兔小贝`
- `type`: `3`
- `api`: `./lib/drpy2.min.js`
- `ext`: `./js/兔小贝.js`
- [规则正文](https://github.com/gaotianliuyun/gao/blob/master/js/兔小贝.js)：1,009 字节；SHA-256 `7173a949be786609d3c16cd02d9797889c6086a485aeff2f29bc77c602dc4676`。

真实网络链：

1. [儿歌列表](https://www.tuxiaobei.com/list/mip-data?typeId=2&page=1&callback=) 返回 JSONP 括号包裹的 JSON，30 项；故事 `3`、国学 `4`、启蒙 `25` 在相同请求头下也各返回 30 项。
2. [小小美人鱼详情](https://www.tuxiaobei.com/play/2140)、[Fruit party 详情](https://www.tuxiaobei.com/play/3257) 均 200，HTML `video-src` 指向 `resource-cdn.tuxiaobei.com` 的 MP4。
3. 对两条媒体仅请求 `Range: bytes=0-4095`，均返回 206、`video/mp4`，文件头具有 MP4 `ftyp`。总大小分别为 8,252,460 / 9,443,552 字节。**这仅验证字节访问，未完成解码或听音验收。**

请求头有实际影响：普通 `okhttp/4.12.0` UA 在故事/国学/启蒙请求中返回 404，iPhone Safari UA 与 Referer 下返回正常。不能把这种 404 误判为分类不存在。原规则本来就指定移动 UA，播放提取进一步指定 iOS UA。

现 drpy 依赖的障碍：

- [gao/lib/drpy2.min.js](https://github.com/gaotianliuyun/gao/blob/master/lib/drpy2.min.js) 导入 `assets://js/lib/cheerio.min.js`、`assets://js/lib/crypto-js.js`。当前聚映 JavaScriptRuntime 模块加载器只支持 HTTP(S) 解析。
- 它还静态导入 `down.nigx.cn/qu.ax/` 下的 `cLFE.js`、`kOUW.js`、`ucoN.js`、`XUKQ.js`、`wYCz.js`；五个地址本次请求均 403。
- [XYQ 的 drpy2](https://github.com/xyq254245/xyqonlinerule/blob/main/dr_py/libs/drpy2.min.js) 也依赖上述 assets URI，模板与 gbk 改为相对模块；本轮仅静态读取，未运行。
- 饭太硬解码配置也含兔小贝（`key=dr_兔小贝`），其 [fantaiying7/EXT 运行库](https://github.com/fantaiying7/EXT/blob/main/drpy2.min.js) 直接从 GitHub 可读取，依赖同仓 `node-rsa.js`、`pako.min.js`、`模板.js`、`gbk.js`、`json5.js`、`jinja.js` 及上述两个 assets 模块，没有 gao 的五个 `down.nigx.cn` 依赖。但配置实际使用的 `git.yylx.win` 代理 URL 本机请求超时，不能把直接 GitHub 可读等同于原配置链可用。

证据：`build/tvbox-audit/{dependencies,upstream,content-confirm,txb-chain}.json`。

## 其他影视与少儿候选

### XYQ：柚子资源

`key=柚子资源`，`type=0`，`api=https://api.yzzy-api.com/inc/api.php`。本轮可读取标准 XML 分类与影片详情；`ac=videolist&ids=108424` 取得一条 HLS 地址。

但对该新片 HLS 以及另一条旧片 HLS 的抽测，常规 UA+Referer、无 Referer 的 OkHttp UA、移动 UA 均得到 403。此结果只反映本机当前网络，不证明所有设备或所有影片都不可播。

分类中既有电影、连续剧、动漫，也有福利 `19`、倫理片 `61`、擦边剧 `118`。不能将整个分类表直接当家庭默认入口。短剧 `83` 本次没有取得影片列表。

聚映已实现 `CMS_XML` 分类、列表与详情解析，并有解析测试；该站的媒体 403 未因此解决，不能把格式兼容算成实际可播放。

证据：`build/tvbox-audit/{content-chains,content-confirm,cms-media,cms-media-confirm}.json`。

### gao：有声绘本 / 童趣

- `drpy_js_有声绘本网`：规则只 550 字节，但源站现已跳转到 `www.youhaoting.com`。旧选择器与播放链未验证，先不选。
- `drpy_js_童趣`：`www.boosj.com/baby/` 本次 TLS 握手失败。属于本机网络证据，先不选，不能据此断言服务永久关闭。
- gao 中除 drpy 外的独立 JS 是路飞搜索、磁力、直播与 Alist；没有发现可直接作为影视/短剧候选且无需未审查运行库的独立 ESM。

## GitHub 维护证据

以下时间是对应配置文件的最近提交时间，不是仓库所有文件的最后更新时间，也不构成可播放保证。

| 配置 | 最近提交（UTC） | 可复核提交 |
|---|---|---|
| gao/js.json | 2024-10-10 13:43:27 | [8caadc1](https://github.com/gaotianliuyun/gao/commit/8caadc1cf0a54dfe438368992d63ff62cae148ab) |
| XYQTVBox.json | 2026-06-11 02:30:34 | [e72edb1](https://github.com/xyq254245/xyqonlinerule/commit/e72edb16454dbecc32af5f6bdd7a315a63d8792b) |
| XC.json | 2026-10-21 06:27:39 | [52b84de](https://github.com/yoursmile66/TVBox/commit/52b84de641ccfba1f05620242540796ca1943feb) |
| wx.json | 2026-09-15 07:38:21 | [7fec69c](https://github.com/wxrjck/-YSC-/commit/7fec69c8ea6cc956d30798386852495b0ba11d1c) |

## 尚需完成

1. 多层仓库选择、完整 drpy assets/HTML/加密桥、通用嗅探与代理。
2. 摸鱼儿的原生依赖、短剧 XBPQ 及其他未选站点的逐项兼容验证。
3. 更长时间、多影片、多网络及音频实听验收；上游变更后重新验证预置。

本报告没有审计全部 JAR 字节码、判定内容授权或验证所有影片。设备抽测结果不代表整个订阅仓库均可用。
