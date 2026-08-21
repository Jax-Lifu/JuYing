# 聚映 juying

一个面向手机、电视、车机与桌面的家庭媒体聚合应用。当前已完成产品骨架、CCTV 公开片库接入和原生 HLS 播放；账号、同步、NAS 与其他来源仍保留为后续模块。

## 当前范围

- Flutter 统一界面：iOS、Android、Windows、Linux；macOS/Web 可作为后续自然扩展。
- 专用宿主预留：Android TV、tvOS、Android Auto、CarPlay。
- 多来源模型：CCTV 官方网页、用户自有 WebDAV、用户自有或已授权的 HTTPS M3U 直播清单。
- 首页、统一搜索、儿童空间、家庭媒体库、设置中心的响应式界面骨架。
- 简体中文、英文文案骨架；亮色、暗色、跟随系统主题。
- 儿童年龄段、家长 PIN、时长、时段、内容分级等配置模型。
- NAS 协议占位：SMB、WebDAV、NFS、Jellyfin、Plex、Emby。
- 无障碍、遥控器焦点、离线缓存、隐私与合规能力预留。

## 运行

本机需要先安装 Flutter stable（建议以项目 CI 固定的版本为准）：

```bash
cd apps/juying_app
flutter create --platforms=android,ios,windows,linux --project-name juying --org com.flytech .
flutter pub get
flutter run -d windows
```

Windows 也可以直接运行 `tool/bootstrap_platforms.ps1`。该命令只生成 Flutter 官方平台 Runner；Android TV、tvOS 与车机仍按 `platform_hosts` 中的专用宿主说明推进。

当前使用 Flutter 3.47.0 / Dart 3.13.0 完成分析与测试。

## 添加直播来源

在“媒体库 → IPTV 直播清单”中输入不含账号的 HTTP(S) M3U、TXT 或分组 JSON 地址，并确认拥有访问和播放权限。验证通过后，该来源会进入统一来源注册表，可在媒体库浏览、在全局搜索中检索，并使用原生播放器播放。播放器支持多线路、相对地址、来源/频道级 `User-Agent`、`Referer`、`Origin`，以及 FongMi 常用的 `#EXTVLCOPT`、`#EXTHTTP` 和 URL 尾部请求头写法。

“设置 → 内容来源”还可导入 TVBox HTTP(S) 配置。应用接入其中的直连 `lives`（外部或内嵌 M3U/TXT/JSON）及 type 0/1/4 标准 XML/JSON 站点；`spider`、`parses`、JAR、JS、Python、代理、DRM、Cookie 和 token 配置不会被执行或导入。

## 重要边界

“免费”指接入方依法公开免费提供、用户自有或已获授权的内容，不表示本项目提供任何绕过会员、地域限制、DRM、广告、签名或鉴权的能力。默认 CCTV 来源使用官网页面自身公开调用的片库、节目页和播放元数据链路，优先原生播放 HLS；受保护、版权无效、无公开 HLS 或接口变化时降级到官网。该链路不是 CCTV 正式对外承诺的开放 API，生产发布前仍需确认授权。详见 [合规边界](docs/COMPLIANCE.md)。

## 文档

- [架构说明](docs/ARCHITECTURE.md)
- [平台能力矩阵](docs/PLATFORM_MATRIX.md)
- [产品范围与路线图](docs/ROADMAP.md)
- [防返工基础规划](docs/FOUNDATION_PLAN.md)
- [合规边界](docs/COMPLIANCE.md)
- [应用示例配置](configs/app.example.json)
- [来源示例配置](configs/sources.example.json)
- [多源可配置机制](docs/MULTI_SOURCE_CONFIGURATION.md)
