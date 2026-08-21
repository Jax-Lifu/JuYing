---
name: video-player-core
description: >-
  Guide for cross-platform video playback, hardware decoding fallback, media_kit (libmpv),
  aspect ratios, subtitle sync, audio track switching, danmaku rendering, and TV D-Pad focus controls.
---

# Video Player Core & TV Interaction Skill

This skill provides architectural patterns, APIs, and guidelines for developing and maintaining the cross-platform video playback engine in JuYing.

## 1. Core Principles
- **Unified Engine**: Use `media_kit` backed by `libmpv` across all platforms (Windows, Linux, macOS, Android, iOS, Android TV).
- **Hardware Decoding Fallback**: Default to hardware acceleration (`d3d11va`, `nvdec`, `vaapi`, `videotoolbox`, `mediacodec`). If video texture creation fails or crashes with decoder errors, catch the exception and gracefully fallback to software decoding (`auto-safe` -> `sw`).
- **Aspect Ratio Control**: Support dynamic video aspect ratio modes:
  - `fit` (Letterbox / Original ratio)
  - `fill` (Stretch to fill viewport)
  - `cover` (Crop to fill 16:9 / 21:9)
  - `16:9`, `4:3`, `21:9` (Fixed aspect overrides)

## 2. Advanced Audio & Subtitle Handling
- **Subtitle Sync & Styling**:
  - Provide runtime subtitle delay adjustment: `±100ms` steps.
  - Support external `.srt`, `.vtt`, `.ass`/`.ssa` tracks.
  - Allow font size, color, outline width, and vertical position custom styling.
- **Audio Track & Channel Offset**:
  - Support multi-audio track switching (Original, Mandarin, Commentary, Stereo, 5.1).
  - Provide audio delay adjustment (`±50ms` steps) to fix A/V desync in non-standard IPTV streams.

## 3. Danmaku (弹幕) Engine Integration (Kazumi Pattern)
- Layer a transparent `DanmakuView` on top of the video surface.
- Support parsing Bilibili XML / DPlayer JSON format comments.
- Maintain independent timeline synchronization with the playback clock.
- Provide user controls for: Danmaku Opacity (0% - 100%), Speed, Font Size, Display Area (Top 25%, 50%, Full), Keyword Blocking Rules.

## 4. TV D-Pad Focus & Remote Control
- **Focus Topology**: Every interactive widget must have an explicit `FocusNode` registered in the tree.
- **Focus Visuals**: All focused cards/buttons MUST display a prominent focus border (`focusBorder` theme token) and a scale effect (`1.05x`) for TV viewing distance.
- **Remote Keybindings**:
  - `Select / Enter`: Play / Pause / Trigger Action
  - `Up / Down`: Live Channel Switch / Volume Adjust
  - `Left / Right`: Seek backward (-10s) / forward (+15s)
  - `Menu`: Toggle Audio / Subtitle / Quality / Aspect drawer
  - `Back`: Exit Fullscreen / Close drawer / Navigate back
  - `0 - 9`: Quick Channel Number jump overlay
