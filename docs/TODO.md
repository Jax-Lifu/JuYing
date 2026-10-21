# 聚映 (JuYing) 需求与里程碑实施追踪清单 (TODO)

> 基线规范：《聚映项目指导文档 v0.1 (2026-10-20)》与《项目审计实施计划》  
> 需求编码：PLY (播放) / LIVE (直播) / VOD (点播与TVBox) / LIB (本地与NAS) / CAST (DLNA发送) / DMR (DLNA接收) / APL (AirPlay) / APP (通用)  
> 优先级定义：P0 = MVP 必须；P1 = 首个正式版应有；P2 = 后续迭代；⚠️ = 待验证/先PoC

---

## 🧭 里程碑追踪 (Milestones Roadmap)

### M0：技术验证 (PoC 阶段)
> 目标：把最大的不确定性变成结论，形成 ADR 与风险应对表

- [x] **PoC-1 跨平台 media_kit 播放内核验证**：Windows (D3D11) 与 Android (MediaCodec) 样本集播放与基础硬解回退
- [x] **PoC-2 SMB 大文件 Seek 性能实测**：基于 `dart_smb2` 测试大码率 MKV 文件拖动与 Range 桥接
- [ ] **PoC-3 DLNA 投屏直推与本地代理测试**：向至少 2 台不同品牌电视（如小米、索尼）推送需请求头的 URL 并走代理
- [ ] **PoC-4 Android 接收端前台服务与 24h 保活**：对比原生 Kotlin 前台服务与 FlutterEngine 方案的被杀率
- [ ] **PoC-5 AirPlay 方案与许可证审查 (⚠️)**：审查 UxPlay (GPLv3) 与 android-airplay-server，评估隔离方案与视频流可行性
- [x] **PoC-6 QuickJS TVBox 爬虫沙箱**：验证基于 `flutter_js` 的 JavaScript 爬虫执行与网络隔离

---

### M1：骨架与播放闭环 (MVP 基础)
> 目标：代码规范分层、CI、播放页、本地文件、M3U 导入与基础设置，两端安装包可用

- [x] **PLY-01 [P0]**：基于 libmpv 播放 HTTP(S)、HLS、FLV、TS、RTSP、RTMP 与本地文件
- [x] **PLY-02 [P0]**：硬解优先（Windows D3D11VA、Android MediaCodec），失败自动回退软解（`hwdec: no`）
- [x] **PLY-03 [P0]**：基础播放控制：播放/暂停/拖动/倍速/音量/静音/全屏
- [x] **PLY-06 [P0]**：断点续播、播放历史本地记录
- [x] **PLY-07 [P0]**：每源可配置自定义请求头（UA/Referer/Cookie）与代理
- [x] **PLY-08 [P0]**：缓冲策略配置与断线自动重试
- [x] **LIB-01 [P0]**：本地视频文件与目录浏览播放
- [x] **LIVE-01 [P0]**：导入 M3U/M3U8 与 TXT 分组源，支持 URL 与本地文件，自动检测编码（UTF-8/GBK）
- [x] **APP-01 [P0]**：源管理中心：直播源、点播源、NAS 共享统一入口
- [x] **APP-02 [P0]**：响应式布局：自适应桌面窗口、平板与手机
- [x] **APP-03 [P0]**：设置中心：播放、网络、外观、字幕、快捷键
- [ ] **APP-07 [P1]**：配置导入导出、备份恢复（版本化 Schema）

---

### M2：直播完整 (日常可用直播)
> 目标：换台首帧达标（≤2s）、线路失败自动熔断、EPG 正确显示、默认 CCTV 合规预设

- [x] **LIVE-02 [P0]**：预置 CCTV 官方示范源方案（tv.cctv.com/yxg 动态解析），支持用户编辑与一键删除（ADR-005）
- [x] **LIVE-03 [P0]**：直播分组、频道搜索、频道收藏、最近观看、台标展示
- [x] **LIVE-04 [P0]**：同频道多线路展示与手动无缝切换
- [x] **LIVE-05 [P1]**：线路测速、3 秒卡顿与 403/404 故障自动切线、线路评分持久化
- [ ] **LIVE-06 [P1]**：XMLTV (含 gz) EPG 流式解析、当前/下一节目展示、节目单查看
- [ ] **LIVE-07 [P1]**：直播源订阅定时更新、失败保留旧缓存、差分合并
- [x] **LIVE-08 [P1]**：快速换台：遥控器上下键、数字键切台、频道选择浮层、相邻频道解码预热
- [ ] **LIVE-09 [P2 ⚠️]**：回看/时移功能（支持 catchup 模板变量动态插值与时区修正）
- [ ] **LIVE-10 [P2]**：UDP / RTP 组播支持与 udpxy 本地代理转换

---

### M3：NAS 与点播基础 (家庭媒体库)
> 目标：大文件拖动流畅、断网重连正常、外挂字幕自动加载

- [x] **LIB-02 [P0 ⚠️]**：SMB (SMB2/3) 局域网共享发现、浏览与播放，经本地代理解决大文件 Seek
- [x] **LIB-03 [P0]**：WebDAV 客户端接入（含 Alist 挂载与坚果云）
- [ ] **LIB-04 [P1]**：同目录外挂字幕（srt/ass/vtt）自动扫描与挂载
- [ ] **LIB-05 [P1]**：FTP / SFTP 协议支持
- [x] **LIB-06 [P1]**：断线自动重连、Range 边界优化（针对 MKV 尾部元数据快速定位）
- [ ] **LIB-07 [P2]**：NFSv3/v4 协议导出目录完整浏览与流式播放
- [ ] **LIB-09 [P2]**：元数据刮削（TMDB / 豆瓣）、智能海报墙与剧集季集自动归纳

---

### M4：DLNA 投屏发送 (DMC)
> 目标：至少 3 台不同品牌电视稳定投送，防盗链源走本地代理，支持双向进度控制

- [x] **CAST-01 [P0]**：SSDP 组播发现局域网 MediaRenderer，支持手动输入 TV IP 兜底
- [x] **CAST-02 [P0]**：推送媒体 URL 到远端并发送控制指令：Play / Pause / Stop / Seek / 音量调节 / 进度查询
- [x] **CAST-03 [P0]**：本地代理出口（`127.0.0.1:9978/p/{token}`）：为电视提供可访问的 URL（注入防盗链请求头与 NAS 映射）
- [ ] **CAST-04 [P1]**：设备兼容性画像库 (DeviceProfile)：处理不同电视 DIDL-Lite 必填字段、MIME、Range 差异
- [ ] **CAST-05 [P1]**：投屏时手机/电脑作为遥控器，进度条与状态实时双向同步
- [ ] **CAST-06 [P2 ⚠️]**：电视不支持容器（如 MKV/DTS）时通过代理服务无损转封装兜底

---

### M5：DLNA 接收端 (DMR)
> 目标：作为 MediaRenderer 被手机主流 App 发现并稳定推送，Windows/Android 常驻可用

- [ ] **DMR-01 [P1]**：作为 MediaRenderer 被局域网发现（SSDP 广播响应 + 设备描述 XML 生成）
- [ ] **DMR-02 [P1]**：响应 AVTransport、RenderingControl、ConnectionManager 动作
- [ ] **DMR-03 [P1]**：事件订阅机制 (GENA) 与 LastChange 状态实时上报
- [ ] **DMR-04 [P1]**：将推送的 URL 统一封装为 `PlaybackSession` 交由统一播放内核，读取 DIDL 标题与海报
- [ ] **DMR-05 [P1]**：接收端设置：自定义设备名称、接收端开关、局域网来源白名单与配对 PIN
- [ ] **DMR-06 [P1]**：Android 前台服务 + `WifiManager.MulticastLock` 后台保活机制
- [ ] **DMR-07 [P1]**：Windows 托盘常驻图标、开机自启动选项、Windows Defender 入站防火墙放行引导

---

### M6：TVBox 兼容层 (VOD 扩展)
> 目标：主流 TVBox 单仓/多仓配置导入解析，规范实体与候选解耦，平台不支持站点显式置灰

- [x] **VOD-01 [P1]**：点播源通用抽象：分类 / 搜索 / 详情 / 选集 / 播放地址解析
- [x] **VOD-02 [P1]**：TVBox 订阅解析（支持标准 JSON、多仓 `dc.txt`、AES-128-CBC 与 WebP 混淆解密）
- [x] **VOD-03 [P1]**：CMS 接口类（XML/JSON）站点全平台原生解析支持
- [ ] **VOD-04 [P1 ⚠️]**：QuickJS 隔离沙箱完善：支持主流 JS 爬虫（drpy），补齐 32MB 内存硬限制与 6 秒网络硬超时
- [x] **VOD-05 [P1]**：TVBox 配置内的 `lives` 直播源自动解出并同步至 LIVE 直播模块
- [x] **VOD-06 [P1]**：源健康检查与平台能力检测：当前平台无法运行的站点类型（如 Windows 遇 Jar 爬虫）显式置灰并给出说明
- [ ] **VOD-07 [P2 ⚠️]**：Jar / Dex 爬虫支持（仅限 Android，默认关闭，用户需显式授权）
- [ ] **VOD-08 [P2 ⚠️]**：TVBox 解析接口（parses）与 WebView 嗅探引擎

---

### M7：TV 适配、AirPlay 实验与正式测试版 (Beta)
> 目标：Android TV 遥控器焦点全量适配、24 小时长稳无泄漏、发布 Beta 构建

- [x] **APP-04 [P1]**：TV 10 英尺大屏 D-Pad 遥控器焦点感知与导航适配（`TvFocusWrapper` 焦点呼吸动效）
- [x] **APP-05 [P1]**：桌面系统集成：置顶小窗、托盘常驻、键盘全局多媒体键、Windows SMTC 系统媒体控制
- [x] **APP-06 [P1]**：国际化与多语言：简体中文、繁体中文、英文字典化支持
- [x] **APP-08 [P1]**：应用内在线更新检查（GitHub Releases / 自建 CDN JSON）
- [x] **APP-09 [P1]**：本地脱敏日志导出与崩溃日志捕获（`applicationSupportDir/logs` 滚动轮转）
- [x] **APP-10 [P1]**：首次使用引导：空状态指引、扫码导入、局域网手机推送门户（`http://ip:9978`）
- [ ] **APL-01~05 [P2 ⚠️]**：AirPlay 接收端实验功能（UxPlay 桥接，屏幕镜像与音频推流）
- [ ] **PLY-12 [P1]**：专业影音诊断浮层 (Stats for Nerds)：实时展示当前解码器、丢帧率、实时码率与缓冲健康度
- [ ] **长稳与性能验收**：Windows / Android 端 24 小时连续播放测试通过，单 ABI Android 包体优化 ≤ 50MB

---

## 🛠️ 当前工程审计与专项待办 (Engineering Tasks)

1. **安全与代理边界加固**：
   - [x] `LocalProxyServer` 仅绑定局域网/Loopback，启用 6 位配对码与一次性 UUID 令牌
   - [ ] 限制可代理目标地址，增加私有网段与本地端口访问拦截，防止 SSRF 漏洞
2. **代码规范与坏味道清理**：
   - [ ] 审计并关闭所有未释放的 `StreamController`、`Timer` 与原生订阅
   - [ ] 清理剩余硬编码 `Colors.*`，全量接入 `AppThemeColors`
   - [ ] 清理页面残留硬编码中文字符串，补全 i18n 字典键
3. **测试与发布资产**：
   - [x] 建立 `docs/PROJECT_GUIDE.md` 作为项目主线需求与架构指导依据
   - [x] 建立 `docs/adr/ADR-001` ~ `ADR-008` 记录 8 大核心架构决策
   - [x] 建立 `docs/test-matrix.md` 规范真机测试与测试分层要求
   - [x] 建立 `docs/release-checklist.md` 规范合规与发布检查清单
