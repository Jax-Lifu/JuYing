# 路线图

## 第一期（进行中）
- [x] CCTV：电视剧点播（`tv.cctv.com/yxg`，官方高清原生流直出）
- [x] IPTV：源管理 UI、M3U/TXT 文件导入、连接检查、XMLTV/gzip 流式解析、线路失效自动切换
- [ ] TVBox：多仓选择（当前已支持首仓加载）、完整 drpy 宿主扩展、通用嗅探/代理、配置文件导入
- [x] 局域网：SMB 源增删、目录浏览 UI、字幕外挂；凭据 Keystore 加密（真实 NAS 兼容与听音仍需独立验收）
- [x] 日常播放：历史分集信息、退出保存进度、后台返回恢复播放/暂停状态、目录与频道缓存上限
- [ ] 设置：缓存清理入口
- [ ] 电视：4K / HDR / 杜比视界 / 杜比音频在可用目标设备上实测，必要时增加音频直通开关
- [ ] 性能：Baseline Profile + Macrobenchmark（在可用目标设备上测冷启动与列表帧率）

## 第二期
- NAS：NFS（`source:nfs`，`nfs://` DataSource）、Alist（`source:alist`）
- 同步：WebDAV 同步源配置/收藏/历史/设置（`core:sync`）
- 投屏：DLNA 接收端 + 发送端、AirPlay 2 接收端（音频默认开启，镜像用户手动开启）
- 屏保/壁纸：参考 aerial-tv
- 画中画、后台音频（`MediaSessionService`）
