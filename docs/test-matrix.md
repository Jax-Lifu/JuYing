# 聚映 (JuYing) 测试分层与真机矩阵规范

> 基线版本：依据《聚映项目指导文档》第 10 章制定

---

## 1. 测试分层策略

| 测试层级 | 测试范围与重点 | 验证手段与工具 | 准入/通过标准 |
| --- | --- | --- | --- |
| **单元测试 (Unit)** | M3U / TXT / EPG 解析、频道归一化、线路评分、代理服务（Range、HEAD、HLS重写）、SOAP XML 编解码、QuickJS 沙箱边界 | 纯 Dart 单元测试（`flutter test test/...`） | 100% 通过，无回归错误 |
| **协议回放测试 (Fixtures)** | 电视设备 SSDP 发现响应、SOAP 动作往返交互、TVBox 加密订阅解密、XMLTV EPG 边界样本 | 基于抓包夹具（`test_fixtures/`）回放测试 | 覆盖主流品牌电视报文样本 |
| **集成测试 (Integration)** | 真实媒体流样本集播放（HTTP、HLS、FLV、MPEG-TS、HEVC）、音视频轨道切换、硬解降级软解流程、生命周期后台挂起 | `integration_test` 样本集驱动播放 | 首帧起播时间达标，无崩溃 |
| **真机测试 (Matrix)** | 见下文真机覆盖矩阵 | 物理设备与测试机群 | 关键链路全功能可用 |
| **长稳测试 (Endurance)** | 客户端连续播放 24 小时长稳；DMR 接收端局域网常驻 7 天可用 | 挂机自动化脚本与内存监控 | 无崩溃、内存无持续爬升（无内存泄漏） |
| **异常注入测试 (Fault Injection)** | 弱网波动、断网、丢包、DNS 污染/超时、自签过期证书、源返回 403/404/500、端口被占 | 代理模拟器与网络限制工具 | 熔断机制按预期触发，界面提示分类明确 |

---

## 2. 建议真机覆盖矩阵 (Test Matrix)

| 类别 | 建议覆盖范围 | 核心关注点与必测场景 |
| --- | --- | --- |
| **智能电视 / 投屏设备** | 至少覆盖 **4 个** 主流品牌（如：小米/红米、华为智慧屏、索尼/三星、海信/TCL） | 1. DLNA DMC 投屏发现与控制（Play/Pause/Seek/音量）<br>2. 电视端对 MKV / HEVC 格式支持度及本地代理转封装降级<br>3. 外挂字幕在电视端呈现兼容性 |
| **Android 系统版本** | 涵盖 **Android 7.0 (minSdk 24)**、**Android 10**、**Android 13** 以及 **Android 14+** | 1. Android 14 前台服务声明与运行权限<br>2. Android 13+ 通知权限申请流程<br>3. 分区存储 (Scoped Storage) 与本地视频文件访问<br>4. HTTP 明文流量限制与 `network_security_config` 放行 |
| **Android ROM 生态** | 原生 Android (AOSP) + 至少 **2 个国产定制 ROM**（如 MIUI/HyperOS、OriginOS、ColorOS、HarmonyOS） | 1. 锁屏/息屏后 DMR 后台保活机制<br>2. 自启动与电池无限制白名单引导提示<br>3. 浮窗权限与画中画 (PiP) 模式 |
| **硬件终端定位** | 覆盖：<br>- 旗舰手机 (高通旗舰芯片, arm64-v8a)<br>- 中端平板/手机<br>- **低端电视盒子** (1GB/2GB 内存, armeabi-v7a) | 1. 低端盒子上 libmpv 内存开销（≤300MB 目标）<br>2. 4K/1080P HEVC 硬解平滑降级软解表现<br>3. D-Pad 遥控器焦点缩放动效流畅度（60fps） |
| **Windows 操作系统** | **Windows 10** 与 **Windows 11**<br>- 覆盖单网卡与多网卡（VPN、Hyper-V/WSL、移动热点）<br>- 覆盖有无 Apple Bonjour 运行库环境 | 1. Windows Defender 防火墙入站放行引导<br>2. SSDP / mDNS 组播在多网卡下的接口智能选择<br>3. 系统媒体控制 (SMTC) 与键盘全局多媒体键<br>4. D3D11VA 硬件加速解码与高 DPI 缩放 |
