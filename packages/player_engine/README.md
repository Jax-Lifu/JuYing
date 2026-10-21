# juying_player_engine

播放引擎核心抽象包（遵循 ADR-002 与 Section 5.3 规范）。

## 核心职责 (What)
- 定义 `PlayerEngine`、`PlayableOption`、`TrackId` 与 `EnginePlayerState` 统一接口契约。
- 封装音轨/字幕轨选择、时序调整、倍速与缓冲状态流。

## 设计动机 (Why)
隔离具体底层解码管线与 Flutter 界面层，为双端默认使用 `media_kit` (libmpv) 及低端盒子备选引入 Android Media3 提供中立协议基底。
