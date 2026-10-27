# 点播与脚本兼容范围

## 使用入口

在「播放源管理 → 添加播放源 → TVBox」输入可信的 HTTP(S) 单仓、多仓或 CMS JSON 接口地址。点播页先选订阅，再选子站和分类；列表按实际视口高度提前一屏加载下一页，封面沿滚动方向提前准备一屏，追加时不显示加载动画，短分页会继续补足；失败后保留已有内容并显示重试。详情页选择播放线路与分集。搜索从已启用且声明可搜索的源和子站逐个返回结果，显示失败与超时，允许保留已有结果后重试。

上滑列表时分类固定在顶部；详情页的返回、播放和收藏使用图标。播放器使用顶部片名、底部进度与控制栏，上一集/下一集只在当前线路内切换，首尾禁用；已移除固定前后 10 秒按钮。清晰度菜单读取当前流可用的视频轨道，支持手动选择和自动模式，单轨流会说明只有一种清晰度。手机竖屏控制项分行，TV 按钮增大并支持方向键焦点，进度条仍支持拖动和遥控器调节。

按用户要求，本次预置肥猫配置中的金牌、急救两个站点。它们以普通来源保存，可编辑、停用或删除；删除后重启不恢复。`extra.siteKey` 绑定的来源只展示和搜索该站点，不作为直播来源展示；手动添加完整订阅仍显示全部子站。订阅与站点会随上游变化，抽测记录见 [预置候选审查](TVBOX_PRESET_AUDIT.md)。

多仓默认使用首仓；已有配置中的 `extra.repoUrl` 可以指定仓库。当前表单不提供本地文件导入或多仓仓库选择。

## TVBox

| 站点 | 已实现的契约 |
|---|---|
| CMS XML（type 0） | `rss/class/ty`、`rss/list/video/dl/dd`，分类/详情 `ac=videolist`，直接播放分集 URL；拒绝 DTD |
| CMS JSON（type 1） | `class/list`，`ac=detail`，`t/pg/ids/wd`，多组 `vod_play_from/vod_play_url`，站点请求头 |
| Jar（type 3） | 含 DEX 的 Jar，`csp_` 类名，`com.github.catvod.crawler.Spider` 的 init/home/category/detail/search/player 方法；可选 MD5 校验 |
| JS（type 3） | QuickJS，ES module 默认对象或工厂、相对 HTTP(S) 静态导入、旧式 `__jsEvalReturn`，`req/request/fetch` 网络桥 |
| Python（type 3） | CPython 3.11，`Spider` 类、`base.spider.Spider`，requests、BeautifulSoup、lxml；两参或三参 searchContent |
| HTTP Spider（type 4） | 通过 HTTP 调用分类、详情、搜索和播放参数 |

各语言最终使用同一 JSON 内容协议。内容 ID 始终包含子站身份；分集引用包含节目、线路、分集名称和位置，避免不同站点的相同 ID 混淆。播放解析返回的请求头随当前地址交给播放器。`parse=1`/`jx=1` 会先尝试订阅配置的 type 1 JSON 解析器，取得媒体地址后交给原生播放器；未解析出原生地址时明确提示，不打开网页播放器。解析器请求只携带其自身配置的请求头，最终播放请求合并站点、解析器与响应提供的请求头。

配置支持 FongMi 图片/Base64 与 2423 AES 包装、中文域名、重定向后的相对 api/jar/ext 地址。JAR 宿主补齐可选全局 Init、真实 Application 上下文、safeDns、SpiderDebug 和 Gson。

这不是任意 TVBox 客户端运行环境的完整复刻。完整 drpy 的 assets/HTML/加密桥、Node/npm、第三方私有桥接库、动态 HTTP 模块导入、Python 任意依赖安装、`proxyLocal` 本地代理及通用网页嗅探尚未实现。依赖这些扩展的站点会失败，不能因脚本语言受到支持就认定该站点可用。

脚本在独立进程中按需执行，串行共享一个运行时，取消或超时后回收进程，空闲时释放；不会在 Application 启动时预热。该进程与宿主共享 Android UID，属于故障隔离，不是权限沙箱。请只添加可信订阅。

## 央视

沿用旧版聚映的官方栏目分类、专辑 ID、GUID 分集和主片筛选逻辑。专辑按每页 100 集读取并按 GUID 去重；已知总数未读完时遇到重复页或失败，会提示重试，不把不完整列表当作成功。

点播默认使用「央视高清（原生播放）」：从官方 H5E 清单选择最高分辨率、同分辨率下最高码率的高清线路，经 H.264 MPEG-TS 分片处理后交给 Media3 原生播放，支持完整点播时间线与拖动。缺少高清线路、最高档编码不支持或清单格式不支持时明确报错，不自动降为标清。用户可手动选择「官方标清（原生播放）」。点播不再提供网页入口；旧版官方网页播放历史自动解析为原生高清，并保留续播和选集。

央视直播使用官方 CDRM/H.264 清单原生播放，保留上游提供的多个清晰度。每次打开频道默认固定最高分辨率、同分辨率下最高码率；清晰度菜单可手动切换或选择「自动」。具体档位随频道和官方清单变化，不补造不存在的高清档位。播放器仅在存在两条以上播放线路时显示「线路」按钮，单个央视官方入口不显示该按钮。

原生高清解码部分移植自旧 Flutter 工程提交 `331aa2972d2d4f4ec0b9c4f888632f0d36105310`，新增 Android JNI 与 Media3 DataSource 连接。第三方 H5E 实现的来源与修改记录见 [溯源说明](../source/cctv/src/main/cpp/third_party/cctv_h5e/README.md)，保留 [GPL-3.0 版权声明](../source/cctv/src/main/cpp/third_party/cctv_h5e/LICENSE) 和 [完整许可证](../source/cctv/src/main/cpp/third_party/cctv_h5e/COPYING)。当前支持 H5E/H.264 完整 TS 点播清单和 CDRM/H.264 TS 直播清单，不包含 UDRM、Widevine 或 HEVC 解码支持。

央视没有在此实现全站全文搜索。当前搜索继承旧版的栏目目录匹配方式，按页匹配片名或演员；单字母可用官方首字母参数。当前页无匹配时仍可继续下一页。

## 验证边界

JVM 测试覆盖协议解析、分页、子站路由、独立搜索失败、取消与重试。常规设备测试使用本项目原创 Jar/JS/Python 站点验证真实解释器和进程调用；第三方公开站点必须显式选择后单独执行，不能用原创测试通过推断所有脚本可用。

2026-10-27 央视直播多清晰度专项验证：

- APK：`dist/v0.1.0_20261027/JuYing_debug_0.1.0_20261027.apk`，SHA-256：`57fed2ee20d60d0a9793c4ab8a413ae69ce246ecd1f2d7972ef8300feae57855`。Cayin 已安装包、构建产物及 dist 文件哈希一致。
- 央视源、Media3 与播放器模块共 54 项单元测试通过；Debug 主包和测试包构建通过。
- Cayin / Android 14 上 `officialLiveQualityDefaultsHighSwitchesAndRestoresAuto` 通过：CCTV-1 首次解码 1280×720；通过真实清晰度菜单依次切至 640×360、854×480、1024×576，再切回 1280×720，最后恢复自动。各阶段均检查实际解码尺寸、连续播放进度和 Surface 截帧非纯色；自动模式清除固定档位，单线路按钮隐藏。日志：`build/cctv-live-quality/device.log`，结果 `OK (1 test)`。
- 本次未重跑其他频道和全工程设备回归，未验收长时播放、音频实听或 Release/R8；档位数量与最高分辨率取决于官方清单。

2026-10-27 央视原生高清移植专项验证：

- Cayin 上显式执行官方《小小围棋少年》播放测试，Media3 + SurfaceView 确认 1280×720、首集完整时长 439480 ms，进度约 3 秒 → 前跳 121 秒 → 回退 21 秒；切换第二集后确认完整时长 439800 ms、进度超过 3 秒。两集均通过 Surface 截帧非纯色检查。日志：`build/ux-12/cctv-hd-device.log`，结果 `OK (1 test)`。
- 上述结果验证真实网络、JNI 分片处理、原生解码与前后拖动；真实 PlayerActivity/Hilt 路由、页面操作与最终包结果见 [12 项体验验证](UX_12_VERIFICATION_20261027.md)。长时连续播放与音频实听尚未验收。

2026-10-27 列表与封面提前一屏加载专项验证：

- APK：`dist/v0.1.0_20261027/JuYing_debug_0.1.0_20261027.apk`，SHA-256：`2c0233cf62f1f088faccdf125304b23b36cbd36bfacc2c9364a6cee4f65f3448`。Cayin 已安装包、构建产物及 dist 文件哈希一致。
- 点播模块 4 项单元测试通过；Debug 主包和测试包构建通过。
- Cayin 上 `vodLoadsNextPageWhenScrolledNearEnd` 通过：距底部约一屏触发下一页，慢请求期间保留旧内容且不显示加载动画，重复滚动不重复请求，短分页无需再次滚动即可补足，末页停止。封面测试在滚动前确认可见 8 项、已准备 16 项，滚入视口后保持同一图片对象；反向滚动再切分类仍能在顶部提前准备下一屏。日志：`build/vod-cover-prefetch/device.log`；画面：`build/vod-cover-prefetch/15-vod-cover-prefetch.png`。
- 本次只复测上述分页与封面行为；未重跑下方完整设备回归及第三方站点抽测，也未完成低配 TV 连续换向的帧耗时测试。极慢网络或快速连续滑动仍可能先到达已加载内容的末尾。

2026-10-26 上一版完整交付验证（以下结果对应当日 APK）：

- APK：`dist/v0.1.0_20261026/JuYing_debug_0.1.0_20261026.apk`，SHA-256：`3e5d81f6d606ba3dbd71db32546f4b3b8f83a3d84574f08d5bf9dd0ed81dcfca`。
- 全工程 67 项 JVM/Android 单元测试通过；Debug 主包和测试包构建通过。
- Cayin / RK3576 / Android 14 上常规设备测试 20 项通过；测试运行器显示 `OK (22 tests)`，其中两个公开网络用例因未提供参数按设计跳过。日志：`build/player-ui-final-device-tests.log`。
- 在同一交付 APK 上另外显式执行肥猫两个站点：金牌搜索 8 项、原生播放 1920×808；急救分类浏览与原生播放 1280×720，两者进度均超过 2 秒。日志：`build/tvbox-audit/device-feimao-delivery.log`。设备已安装包、构建产物及 dist 文件的 SHA-256 一致。
- 设备测试覆盖点播自动翻页与末页停止、分类吸顶、上下集首尾边界和选集、遥控器焦点、来源表单检查/保存/编辑/删除、XMLTV/gzip/外部实体拒绝、旧凭据迁移与加密、防止迁移覆盖并发编辑、预置删除不复活、频道缓存配置隔离、历史数据库迁移，以及播放后台返回保持播放或手动暂停状态。
- 原创双清晰度 HLS 测试在同一设备上确认解码尺寸 320×240 → 160×120、恢复自动轨道选择、1.5 倍速；它验证播放器选轨机制，不代表外部站点会提供多个清晰度。最新页面截图在 `dist/v0.1.0_20261026/player-ui/`；旧 `ui-check/` 属于较早包的页面记录。
- 完整 drpy、通用嗅探/代理、真实 NAS、系统文件选择器授权持久化的端到端操作、长时播放与音频实听、4K/HDR/杜比、手机/平板/TV 实体设备的完整布局回归和 Release/R8 尚未验收。三端资源选择与 TV 控件尺寸有自动测试，当前包的实际画面与方向键操作在 Cayin 验证。网盘仍不在本轮范围。

2026-10-26 早期阶段验证记录（以下哈希不是当前交付包）：

- 全工程单元测试共 42 项，失败 0；Debug 主包和测试包编译通过。
- MX7A / Android 12 上，最终 APK 的 6 项 Instrumentation 测试全部通过：Jar、现代 JS、旧版 JS、Python、取消死循环 Python 后立即重连 JS，以及 CMS 分类→列表→搜索→详情→分集解析→Media3 SurfaceView 播放。
- CMS 使用原创 320×240 无声测试片，确认视频尺寸、总时长与进度超过 1 秒。素材 `app/src/androidTest/assets/test-pattern.mp4` 由 FFmpeg `testsrc2=size=320x240:rate=24` 生成，8 秒、H.264，不包含第三方节目。
- 本轮页面实测确认央视目录、详情、封面及官方网页视频画面；按钮着色和宽屏列数问题已修正。网页画面不等于原生高清或听感验收。
- 最终 APK：`dist/v0.1.0_20261026/JuYing_debug_0.1.0_20261026.apk`，SHA-256：`799eb68466c54d9031f6130f7e4a88a40b0c97cf1caca94c05729ce01d7dabe4`。
- 首选 `qytech6666` 未连接，未完成该设备复测；手机、平板的实体设备与第三方订阅兼容性仍需单独验收。未执行 Release 构建。

实现参考 [LibreTV 行为评估](research/2026-10-26-libretv-assessment.md)，未复制其代码。JS 异步与模块调用遵循 [QuickJS-KT 接口](https://github.com/dokar3/quickjs-kt#async)。
