# 路线图

## 第一期（进行中）
- [ ] CCTV：迁移现有官方公开地址逻辑 → `CctvSource.resolve`；电视剧点播（tv.cctv.com/yxg）
- [x] IPTV：源管理 UI、M3U/TXT 文件导入、连接检查、XMLTV/gzip 流式解析、线路失效自动切换
- [ ] TVBox：CMS(type 0/1) → jar(type 3, `JarSpiderLoader`) → js → py；多仓选择；解析/嗅探
- [x] 局域网：SMB 源增删、目录浏览 UI、字幕外挂；凭据 Keystore 加密（真实 NAS 兼容与听音仍需独立验收）
- [x] 日常播放：历史分集信息、退出保存进度、后台返回恢复播放/暂停状态、目录与频道缓存上限
- [ ] 设置：解码模式、帧率匹配、缓存清理
- [ ] 电视：4K / HDR / 杜比视界 / 杜比音频在目标设备（如 mx5）上实测，必要时增加音频直通开关
- [ ] 性能：Baseline Profile + Macrobenchmark（在 mx5 上测冷启动与列表帧率）

## 第二期
- NAS：NFS（`source:nfs`，`nfs://` DataSource）、Alist（`source:alist`）
- 同步：WebDAV 同步源配置/收藏/历史/设置（`core:sync`）
- 投屏：DLNA 接收端 + 发送端、AirPlay 2 接收端（音频默认开启，镜像用户手动开启）
- 屏保/壁纸：参考 aerial-tv
- 画中画、后台音频（`MediaSessionService`）
- 与 Windows 端保持一致的外观与行为（共享协议与数据格式）
