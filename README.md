<div align="center">

# 聚映 (JuYing)

**面向家庭网络的现代化跨平台视频播放与媒体聚合客户端**

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20%7C%20Android%209%2B%20%7C%20Android%20TV-blue.svg)](https://flutter.dev)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.16.0-02569B.svg?logo=flutter)](https://flutter.dev)
[![Engine](https://img.shields.io/badge/Engine-media__kit%20%2B%20Media3%20(Dual--Engine)-E05D44.svg)](https://mpv.io)
[![Architecture](https://img.shields.io/badge/Architecture-Clean%20%2B%20Monorepo%20(11%20Packages)-success.svg)](docs/PROJECT_GUIDE.md)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)

*把 IPTV 直播、点播源（含 TVBox 配置）、NAS 与本地媒体放进同一个播放界面；既能把内容投到局域网电视，也能作为 DLNA / AirPlay 接收端被手机和电脑投屏。*

</div>

---

## 🎯 项目定位与典型场景

依据 **[《聚映项目指导文档 v0.2》](docs/PROJECT_GUIDE.md)**，本项目的主线目标平台为 **Windows 10/11** 与 **Android 9+ (minSdk 28，手机/平板/Android TV 首发同时支持，ADR-011)**；applicationId: `com.flytech.juying`。所有平台共用统一的领域模型、业务契约与底层抽象，杜绝碎片化重复实现。

| 场景 | 设备形态 | 核心行为与职责 |
| :--- | :--- | :--- |
| **客厅大屏** | Windows 接电视；Android 盒子/电视 (TV) | 遥控器大屏看直播、点播，被手机多屏投屏；4K/HDR/杜比视界自适应切换 |
| **桌面书桌** | Windows 桌面电脑 (便携/安装双形态) | 高画质看直播、点播，浏览 NAS 资源，托盘常驻为 DLNA / AirPlay 接收端 |
| **移动便携** | Android 手机/平板 | 随时随地观看，一键将媒体流与请求头推送到电视大屏，支持 WebDAV 多端同步 |

### 5 大核心设计原则
1. **播放双内核架构（libmpv + Android TV Media3，ADR-002 / PLY-13）**：通用场景采用 `media_kit` (libmpv) 保证格式全覆盖；Android TV 端引入 `Media3` (ExoPlayer) 支持 4K、HDR、杜比音频直通与杜比视界硬件解码。
2. **内容与应用解耦（ADR-005）**：应用**严禁内置、分发或运营任何第三方媒体源**；默认源仅为用户可查看、可编辑、可删除的示例预设。
3. **协议层与 UI 层分离（ADR-007）**：协议解析（M3U、XMLTV、SOAP、Range、WebDAV 同步）脱离 Flutter 框架，在纯 Dart 命令行与测试环境中 100% 独立运行。
4. **Apple 风格设计语言与原生焦点导航（ADR-010）**：以 Cupertino 为基底，集中收口 `ui_kit` 设计令牌；内置低性能模式（Low Performance Mode），在低端电视盒子上自适应降级实时毛玻璃为纯色半透明，保证 60fps 流畅。
5. **最小闭环与分步演进**：核心流媒体闭环先行，实验性功能（AirPlay 音频默认开/镜像可选、TVBox Jar 站点纯 Dart 移植、WebDAV 同步）安全沙箱隔离。

### 明确非目标（当前阶段）
- **不提供或运营任何内容服务器、账号体系或自有云同步服务**（跨设备同步依托用户自配 WebDAV，凭据加密后同步，见 APP-12）。
- **不做 BT / 磁力下载**（离线缓存下载按规范收敛在 P2 范围）。
- **不做 iOS / macOS / Linux 首发承诺**（架构保持中立不排斥，但不承诺、不主动测试，集中精力打磨 Win + Android）。
- **不直连各家商业网盘私有 API**（统一通过 Alist 或 WebDAV 虚拟挂载间接支持）。
- **不做服务端转码**（仅在电视不支持特定容器时于本机微型代理做轻量级重封装）。

---

## 🌟 核心需求能力矩阵 (Requirement Taxonomy)

本项目需求统一按《项目指导文档 v0.2》需求编号进行版本追踪与提交管理：

```text
├── PLY  (播放核心)    : 格式覆盖、D3D11/MediaCodec硬解自愈、多音轨/字幕、断点续播、请求头注入、诊断浮层(PLY-12/13)
├── LIVE (直播/IPTV)   : M3U/TXT解析、CCTV官方规范流、双栈探测、2秒快速切台(LIVE-08)、XMLTV EPG、多线路故障转移
├── VOD  (点播/TVBox)  : CMS接口、QuickJS沙箱、Jar站点纯Dart移植(ADR-008)、实体候选解耦、多仓故障隔离(VOD-09)
├── LIB  (本地/NAS)    : 本地文件、SMBv2/v3、NFS(LIB-07纯Dart实现)、WebDAV/Alist、外挂字幕匹配、断线重连、Range优化
├── CAST (DLNA发送端)  : SSDP发现+手动IP、播放控制、本地代理出口 (127.0.0.1:9978)、标准设备兼容画像
├── DMR  (DLNA接收端)  : 被手机发现、AVTransport/RenderingControl动作响应、前台服务保活、防火墙一键引导
├── APL  (AirPlay接收) : 音频接收默认开启(ALAC/AAC)、屏幕镜像用户自选开启、mDNS广播与安全隔离(APL-01~05)
└── APP  (应用通用)    : 源管理中心、Apple风格设计令牌、低性能模式、WebDAV多端同步(APP-12)、TV焦点、SMTC控制
```

---

## 📐 系统架构与目录结构

聚映遵循 **Feature-First + Clean Architecture + Monorepo** 分层规范，严格保持自上而下的单向依赖：

```text
juying/
├── apps/
│   └── juying_app/                             # 跨平台客户端应用主工程 (Windows + Android 9+)
│       ├── android/                            # Android 原生配置 (前台服务保活/minSdk 28/leanback)
│       ├── windows/                            # Windows Runner 与 Inno Setup 打包脚本
│       ├── assets/                             # 预设清单与国际化词典
│       ├── lib/                                # 客户端 UI 与状态驱动 (Clean Architecture)
│       │   ├── app/                            # 路由表、响应式 Shell、主题 Token、平台能力探测
│       │   ├── features/                       # 业务特性模块 (Live, VOD, Cast, NAS, Player, Sync...)
│       │   ├── core/                           # 应用内基础设施 (适配层、本地代理、弹幕)
│       │   └── shared/                         # 空间焦点包装器 (TvFocusWrapper)
│       └── test/                               # 应用层单元与组件测试套件 (400+ Tests 全通过)
├── packages/                                   # 11 个独立且脱离 Flutter 可测的纯 Dart 模块包
│   ├── core/                                   # 纯 Dart 核心领域模型、标准设备画像、统一 AppFailure
│   ├── player_engine/                          # 双播放内核抽象与调度器 (MpvEngine + Media3Engine, ADR-002)
│   ├── source_providers/                       # SourceProvider 源定义与 TVBox Jar 纯 Dart 移植引擎 (ADR-008)
│   ├── proxy_server/                           # 127.0.0.1:9978 本地 Range 代理服务与 Token 生命周期 (ADR-006)
│   ├── net/                                    # 统一 HttpClient、网络安全策略与编码自动检测
│   ├── storage/                                # WebDAV LWW 同步冲突仲裁器与硬件安全凭据库 (APP-12)
│   ├── epg/                                    # XMLTV 流式解析与频道名归一化清洗
│   ├── discovery/                              # SSDP / mDNS 服务发现与网卡选择
│   ├── cast_sender/                            # DLNA 投屏发送端 (DMC) 核心状态机
│   ├── receiver/                               # DLNA 接收端 (DMR) 协议与 DIDL 解析
│   └── ui_kit/                                 # Apple 风格设计令牌、毛玻璃组件与低性能降级策略 (ADR-010)
├── native/                                     # 原生系统扩展与三方运行时
│   ├── android/                                # Kotlin: MulticastLock、前台服务保活
│   ├── windows/                                # C++: SMTC 系统媒体控制、防火墙引导
│   └── third_party/                            # libmpv、UxPlay 构建脚本与 SHA-256 校验
├── test_fixtures/                              # 协议回放抓包与格式测试夹具
│   ├── playlists/                              # M3U / TXT / EPG 边缘样本
│   ├── tvbox_configs/                          # TVBox 单仓/多仓/加密配置样本
│   └── dlna_captures/                          # 各品牌电视的 SSDP / SOAP 抓包回放
├── docs/                                       # 项目架构规范与决策记录
│   ├── PROJECT_GUIDE.md                        # 聚映项目指导文档 v0.2 (SSOT 权威主文档)
│   ├── adr/                                    # 11大架构决策记录 (ADR-001 ~ ADR-011)
│   ├── test-matrix.md                          # 真机测试矩阵与分层要求
│   └── release-checklist.md                    # 正式发布检查清单与开源合规红线
├── tools/                                      # 工程自动化脚本 (format_all, run_all_tests, build_windows_release)
├── .github/workflows/                          # GitHub Actions CI/CD 流水线 (全包自动化测试)
├── melos.yaml                                  # Monorepo 多包管理配置
├── pubspec.yaml                                # Dart Pub Workspaces 根工作区配置
└── analysis_options.yaml                       # 根工作区静态分析规则
```

---

## 🏛️ 16 大核心架构决策记录 (ADR 概览)

详细决策分析与 Trade-off 评估请参阅 **[docs/adr/](docs/adr/)**：
- **[ADR-001](docs/adr/ADR-001-flutter-framework.md)**：选择 Flutter 而非 Tauri 2（确保原生硬件解码管线与 TV D-Pad 焦点原生控制）。
- **[ADR-002](docs/adr/ADR-002-libmpv-playback-engine.md)**：采用 `media_kit` (libmpv) 作为默认播放内核，并在 Android TV 上针对 4K/HDR/杜比视界引入 Media3 (ExoPlayer) 第二引擎。
- **[ADR-003](docs/adr/ADR-003-dart-dlna-implementation.md)**：DLNA / UPnP 协议栈首选纯 Dart 自研实现，避免跨平台 C/Rust 动态库构建复杂度。
- **[ADR-004](docs/adr/ADR-004-airplay-deferral-poc.md)**：AirPlay 接收端整体后置至 P2 并优先做 PoC（防范 UxPlay GPLv3 许可证传染与私有协议风险）。
- **[ADR-005](docs/adr/ADR-005-no-builtin-content.md)**：应用自身严禁内置、分发或运营任何第三方内容，默认源仅为可删除预设。
- **[ADR-006](docs/adr/ADR-006-unified-local-proxy.md)**：建立统一的微型本地 HTTP Range 代理服务（解决防盗链、NAS 投屏与 Seek 问题）。
- **[ADR-007](docs/adr/ADR-007-monorepo-layering.md)**：代码自上而下严格单向依赖，协议与算法脱离 Flutter 框架独立在纯 Dart 运行。
- **[ADR-008](docs/adr/ADR-008-tvbox-cms-js-first.md)**：TVBox 兼容层优先支持 CMS 与 QuickJS，Jar 站点采用纯 Dart 移植架构（`tvbox/ports/`）。
- **[ADR-009](docs/adr/ADR-009-gpl3-license.md)**：全工程采用 GNU General Public License v3.0 (GPL-3.0) 开源协议。
- **[ADR-010](docs/adr/ADR-010-apple-style-cupertino-design.md)**：采用 Apple 风格视觉规范，以 Cupertino 为基底集中收口设计令牌，提供低性能降级模式。
- **[ADR-011](docs/adr/ADR-011-unified-codebase-mobile-tv.md)**：手机、平板与 Android TV 首发共用单一代码库与统一构建产物。
- **[ADR-012](docs/adr/ADR-012-vertical-slice-monorepo-democking.md)**：垂直切片单体仓解耦与去模拟化交付原则（杜绝假数据，未移植功能明确降级）。
- **[ADR-013](docs/adr/ADR-013-libmpv-universal-first-media3-phasing.md)**：播放引擎分期交付策略：libmpv 通用首发，Media3 杜比第二引擎分期引入。
- **[ADR-014](docs/adr/ADR-014-tvbox-cross-platform-boundary-and-dex-policy.md)**：TVBox 跨平台边界与 Android DEX 运行策略（安全弹窗免责与沙箱隔离）。
- **[ADR-015](docs/adr/ADR-015-dual-port-isolated-proxy-and-lan-gateway.md)**：双端口物理隔离代理与局域网配对网关（127.0.0.1:9978 与 0.0.0.0:9979 隔离）。
- **[ADR-016](docs/adr/ADR-016-apple-ui-and-tv-focus-phased-rollout.md)**：Apple 视觉风格与 TV 焦点防抖分期落地规范。

---

## 🚀 快速上手与运行 (Getting Started)

### 环境要求
- **Flutter SDK**: `>= 3.16.0` (推荐 Flutter 3.24+ / 3.27+)
- **Dart SDK**: `>= 3.2.0 < 4.0.0`
- **Windows**: Visual Studio 2022 (包含 C++ 桌面开发工作负载)
- **Android**: Android Studio / Android SDK (Min SDK 28, Target SDK 34)

### 1. 获取依赖 (Monorepo Workspace)
```bash
# 根目录一键解析全工作区依赖 (Dart Pub Workspaces)
dart pub get
```

### 2. 执行静态分析与全量测试
```bash
# 代码格式化规范校验 (全工作区 100% 格式化)
pwsh -ExecutionPolicy Bypass -File tools/format_all.ps1

# 执行全工作区自动化单元与组件测试 (11 个 packages + apps/juying_app 400+ Tests)
pwsh -ExecutionPolicy Bypass -File tools/run_all_tests.ps1

# 对客户端应用执行严格静态分析
flutter analyze apps/juying_app
```

### 3. Windows 生产级构建与发布打包 (Q9 / Section 3.3)
```bash
# 一键自动生成 Windows 便携版 (Portable ZIP) 与 Inno Setup 安装包 (.exe)
pwsh -ExecutionPolicy Bypass -File tools/build_windows_release.ps1 -Version "0.2.0"
```
产物将输出至 `dist/windows/`：
- `JuYing-v0.2.0-windows-x64-portable.zip`（解压即用便携版，携带 `portable.flag` 数据隔离标识）
- `JuYing-v0.2.0-windows-x64-setup.exe`（Inno Setup 安装包，自动配置防火墙放行规则与桌面快捷方式）
- `SHA256SUMS.txt`（发布二进制哈希校验和）

### 4. 本地调试与启动
```bash
cd apps/juying_app

# 启动 Windows 桌面版 (主力开发验证平台)
flutter run -d windows

# 启动 Android / Android TV 设备
flutter run -d android
```

---

## 📜 遥控器与键盘映射 (Key Bindings)

| 按键 (Key) | 交互上下文 | 触发功能 |
| :--- | :--- | :--- |
| **D-Pad 方向键 / 键盘方向键** | 全局页面 | 空间焦点导航 (带高亮发光边框与呼吸缩放) |
| **OK / Enter / Space** | 列表与卡片 | 确认点击 / 展开详情 / 开始播放 |
| **Space / OK** | 播放器全屏 | 播放 / 暂停切换 |
| **Left (←) / Right (→)** | 播放器全屏 | 快速后退 10 秒 / 快进 15 秒 (长按平滑 Seek) |
| **Up (↑) / Down (↓)** | 播放器全屏 | 音量加减 / 直播模式下快速上下换台 |
| **ESC / Back (返回键)** | 播放器全屏 | 退出全屏 / 返回上级页面 |
| **Menu (菜单键) / D 键** | 播放器全屏 | 唤出 OSD 高级设置抽屉与实时流媒体诊断浮层 (PLY-12 / PLY-13) |

---

## 📄 开源许可证与免责声明

- 本项目软件架构与全部源码采用 **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)** 开源。
- 遵循开源卫生要求，引用与参考的代码保留原作者署名与版权声明。
- 第三方原生库（libmpv、UxPlay）固定发布版本并校验 SHA-256（详见 [发布检查清单](docs/release-checklist.md)）。
- **免责声明**：聚映仅为开源跨平台媒体播放与投屏软件，不内置、不提供、不分发任何受版权保护的音视频内容。
