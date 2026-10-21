# 测试播放列表与 EPG 样本 (Playlists & EPG Fixtures)

本目录用于存放各类标准与边缘格式的播放列表样本，用于协议层流式解析单测与离线回归：
- `standard_extm3u.m3u`: 包含 `#EXTM3U`, `#EXTINF`, `tvg-id`, `tvg-logo`, `group-title`。
- `vlc_headers.m3u`: 包含 `#EXTVLCOPT:http-user-agent` 与 `#EXTHTTP` 自定义请求头。
- `chinese_grouped.txt`: 包含 `频道名称,URL$线路` 分组文本。
- `sample_epg.xml`: 包含标准 XMLTV 节目单与时移回看配置。
