# 聚映 (JuYing) 架构韧性、性能预算与工程自愈规划

> 本文档由 **架构师视角** 梳理，聚焦于聚映在 **弱网离线弹性**、**低端电视盒内存预算**、**无感自愈与在线更新**、**不可信爬虫沙箱防御** 以及 **专业影音可观测性 (Nerd Stats)** 维度的系统级解决方案。

---

## 🛡️ 五大深水区架构规范与实施方案

### 1. 📡 弱网断网与二级持久化缓存 (Offline-First Resilience)
- **核心问题**：网络抖动或离线启动时页面全白/全空，海报未缓存导致二次渲染卡顿。
- **实施规范**：
  - **Stale-While-Revalidate (SWR) 模式**：
    - 针对 CCTV 官方分类/专辑、TVBox 订阅元数据、EPG 节目单，统一持久化至本地 SQLite / 结构化文件。
    - 进入页面立即展示本地快照（秒开体验），后台并发静默拉取增量更新；请求失败时保留旧数据并弹出“离线快照模式”提示。
  - **海报多级缓存策略**：
    - 引入 `cached_network_image` 替代原生 `Image.network`，强制配置磁盘缓存（上限 500MB，LRU 淘汰机制）。
    - 预设高饱和度渐变色块占位图，杜绝大屏滚动时突兀的空白方块。

---

### 2. ⚡ 低端 Android TV 内存预算与防 OOM 屏障 (Low-End Hardware Budget)
- **核心问题**：1GB/2GB 内存电视盒上，海报未缩放解码、聚合搜索无上限并发易引发 Native OOM 崩溃。
- **实施规范**：
  - **图片解码分辨率下采样 (Downsampling)**：
    - 在电视端限制海报图片最大解码分辨率（如 `cacheWidth: 360`, `cacheHeight: 540`），单个纹理内存占用从 32MB 压缩至不足 700KB。
    - ListView / GridView 开启 `addAutomaticKeepAlives: false` 与 `addRepaintBoundaries: true`，离开屏幕立即释放 GPU 纹理。
  - **并发流式收敛与内存水位守卫**：
    - 跨源并发搜索最多挂起 8 个站点同时工作（令牌桶并发控制），单次聚合列表在内存中最多驻留 100 条条目，采用分页流式增量追加。
  - **QuickJS 虚拟机生命周期回收**：
    - 限制单个 QuickJS 运行时最大内存上限为 **32MB**。
    - 页面销毁或用户切换站源时，显式调用 Native C-FFI 彻底销毁 JS 引擎堆栈，严禁闭包全局泄漏。

---

### 3. 🔄 客户端在线更新、规则热更与配置损坏自愈 (Self-Healing & OTA)
- **核心问题**：电视安装麻烦，接口加密或防盗链变更频繁，本地 JSON 损坏卡死启动。
- **实施规范**：
  - **应用内全平台更新器 (App Updater)**：
    - 支持从 GitHub Releases 或自建 CDN 解析最新 Release Tag 与更新日志。
    - **Android TV / 移动端**：应用内后台下载 APK 并直接唤起系统 PackageInstaller（支持 Android TV 遥控器一键确认更新）。
    - **Windows 桌面端**：下载便携包/安装包后自动调用静默覆盖脚本并重启客户端。
  - **动态规则与可用源热更 (Rule Over-The-Air)**：
    - 将 CCTV 解析正则、公共备用 IPTV 直播源、User-Agent 模拟字典设计为热更 JSON，启动时异步拉取差分包，无缝修补已失效的爬虫规则。
  - **坏死配置自动隔离与恢复 (Safe-Mode Fallback)**：
    - 本地反序列化加入严格 Schema 校验与 Try-Catch 兜底；若持久化配置文件损坏，自动将其隔离为 `.bak`，并回退至安全内置默认配置，绝不白屏崩溃。

---

### 4. 🛡️ 不可信爬虫沙箱隔离与隐私数据防护 (Sandbox Security & Privacy)
- **核心问题**：第三方 TVBox JS 脚本存在恶意网络扫描、死循环 DoS、日志窃取 WebDAV 凭据风险。
- **实施规范**：
  - **沙箱能力最小化原则**：
    - QuickJS 沙箱内部严禁注入 `dart:io`、文件系统、环境变量与进程执行通道。
    - 爬虫发起的 `fetch/request` 统一受限重定向至宿主 HTTP Client，强制设置 **6 秒硬超时**，并屏蔽访问本地回环与局域网敏感端口（如路由管理后台）。
  - **输入净化与防注入**：
    - 第三方源返回的媒体标题、剧集 URL、弹幕文本进行 HTML 实体转义与特殊控制字符过滤，严禁在 WebView 或富文本中执行非法注入。
  - **凭据硬件级保险箱**：
    - WebDAV 密码、网盘 OAuth RefreshToken 仅存放于系统硬件加密区（Windows Credential Manager / Android Keystore）。
    - 生产构建默认禁用明文 HTTP Header 日志输出，所有 Token 打印强制脱敏（如 `eyJh***9x`）。

---

### 5. 📊 影音技术统计 HUD (Stats for Nerds) 与网络源体检 (Observability)
- **核心问题**：用户遇到卡顿或黑屏无法定位原因，排查无从下手。
- **实施规范**：
  - **实时影音技术统计 HUD (Stats for Nerds)**：
    - 播放中按遥控器菜单键或长按画面，呼出半透明专业参数浮层：
      - **解码模式**：`D3D11VA (Hardware)` / `MediaCodec (Hardware)` / `Software (CPU)`
      - **实时帧率与丢帧**：`59.94 fps` / `Dropped Frames: 0 (0.0%)`
      - **网络缓冲健康度**：`Buffer Ahead: 24.5s (38.2 MB)`
      - **当前生效参数**：`1920x1080 @ 6500 kbps, H.264 High 4.2 / AAC 2.0 48kHz`
      - **请求往返延迟 (RTT)**：`86ms (CDN: CNTV-BGP)`
  - **全源一键网络体检工具 (Source Speedtest & Health Probe)**：
    - 在设置页面提供“站源与直播线路健康诊断”：一键对当前配置的 50+ 站点进行并发握手测试，生成“延迟 / 成功率 / 是否支持 IPv6 / 评分等级”矩阵表格，并支持“一键停用故障源”。
  - **本地脱敏日志导出**：
    - 设置页提供“导出诊断报告”功能，自动打包生成近 3 次播放的脱敏日志，支持局域网 HTTP 扫码下载。

---

## 🗓️ 三轮审计成果矩阵总览

| 维度 | 对应报告文档 | 覆盖核心内容 |
| :--- | :--- | :--- |
| **第一轮：技术与安全治理** | `PROJECT_AUDIT_ACTION_PLAN.md` | 本地代理鉴权、全局异常捕获、mock 隔离、生命周期管理、静态分析加固 |
| **第二轮：功能与交互盲区** | `FEATURE_ROADMAP.md` | 收藏追剧中枢、自动下一集/跳过片头、画中画小窗、多维筛选、字幕音轨管理 |
| **第三轮：韧性与工程进化** | `RESILIENCE_ROADMAP.md` | 弱网 SWR 缓存、低端电视防 OOM、应用/规则自愈热更、沙箱防御、Nerd Stats |
