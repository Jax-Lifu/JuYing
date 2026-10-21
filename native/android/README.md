# 原生 Android 扩展 (Native Android Extensions)

根据《聚映项目指导文档 v0.1》第 6.1 节规范，本目录用于承载 Android 平台专用原生 Kotlin 代码：
- `MulticastLock`: 申请并持有 Wi-Fi 组播锁，保证息屏/后台时持续收发 SSDP 广播。
- `ForegroundService`: DMR 接收端保活前台服务与通知（适配 Android 14 前台服务类型规范）。
- `MediaSession`: 锁屏媒体控制中心与系统快捷控制。
