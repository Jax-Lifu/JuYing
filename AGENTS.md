# 聚映 (JuYing) 项目工程约束与指导原则

## 1. 核心工程原则
- 本项目为全平台视频播放与媒体聚合客户端（Windows、Android、iOS、macOS、Linux、Android TV）。
- 当前默认主力验证平台为 Windows，所有平台必须共用统一的领域模型、业务用例与数据契约，杜绝重复实现。
- 编译调试时，如果遇到已有进程占用，直接终止（kill）被占用的进程并重新构建。
- 执行命令与修改时默认同意执行，保持敏捷高效。

## 2. 架构与技能规范
- 必须严格遵循 `.agents/rules/juying-architecture-constraints.md` 中定义的架构规范。
- 针对视频播放、IPTV 直播、TVBox 爬虫沙箱、局域网 NAS 协议与 TV 焦点，参考并遵循 `.agents/skills/` 下的各领域技能：
  - `video-player-core`: 播放内核、硬解故障降级、多音轨/字幕延迟与 D-Pad 交互。
  - `iptv-live-engine`: IPTV M3U/TXT、CCTV 动态流、IPv4/IPv6 探测与 3 秒故障切台。
  - `tvbox-spider-sandbox`: QuickJS 沙箱、统一实体/候选分离、搜索防抖与 Epoch 控制。
  - `lan-nas-streaming`: Samba/NFS 协议、本地回环 Range 代理与手机局域网远程配置。
