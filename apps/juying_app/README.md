# JuYing Flutter App

## 初始化与运行

```powershell
flutter pub get
flutter run -d windows
```

也可以使用 `tool/bootstrap_platforms.ps1` 重新补齐官方 Runner 并执行检查。

## CCTV 原生播放链路

1. `CctvRepository.fetchPrograms` 获取官网公开片库列表。
2. `CctvParsers.pageGuid` 只读取节目页显式声明的 GUID。
3. `CctvRepository.resolvePlayback` 获取官网播放器使用的公开元数据。
4. `CctvParsers.playback` 校验播放状态、保护标记、版权标记和 HLS 域名。
5. `CctvPlayerPage` 使用 `media_kit` 原生播放；失败时使用系统浏览器打开官网。

相关实现位于 `lib/infrastructure/cctv` 和 `lib/features/player`。
