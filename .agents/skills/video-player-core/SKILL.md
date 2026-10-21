---
name: video-player-core
description: >-
  Guide for cross-platform video playback, hardware decoding fallback, media_kit (libmpv),
  aspect ratios, subtitle sync, audio track switching, danmaku rendering, TV D-Pad focus controls,
  and playback progress caching.
---

# Video Player Core & TV Interaction Skill

This skill provides architectural patterns, low-level integration rules, and user interaction standards for JuYing's unified video playback engine.

---

## 1. Unified Playback Engine (`media_kit` & `libmpv`)

All target platforms (Windows, Linux, macOS, Android, iOS, Android TV) MUST share the unified `media_kit` playback engine powered by `libmpv`.

### 1.1 Hardware Decoding Strategy & Fallback Cascade
- **Primary Preference**: Enable native hardware decoding per platform:
  - Windows: `d3d11va`, `d3d11va-copy`, `nvdec`
  - Android / Android TV: `mediacodec`, `mediacodec-copy`
  - macOS / iOS: `videotoolbox`, `videotoolbox-copy`
  - Linux: `vaapi`, `vdpau`
- **Automatic Fallback Sequence**:
  1. Initialize with `hwdec: auto-safe`.
  2. Monitor MPV video texture creation events and frame drops within the first 1500ms.
  3. If video rendering throws decoder initialization exceptions (e.g. `MPV_ERROR_DECODER_INIT_FAILED`, green screen texture error, or unsupported 10-bit HDR on low-end SoC), catch the error, record error telemetry, and smoothly re-initialize player with `hwdec: no` (CPU software decoding) without breaking playback position.

```dart
// Decoder fallback pseudo-pipeline
Future<void> initPlayerWithFallback(Player player, String url) async {
  try {
    await player.open(Media(url, httpHeaders: customHeaders));
  } catch (e) {
    logger.w('Hardware decoding failed, falling back to software decoding: $e');
    await (player.platform as dynamic)?.setProperty('hwdec', 'no');
    await player.open(Media(url, httpHeaders: customHeaders));
  }
}
```

### 1.2 Aspect Ratio Control
Support 6 dynamic aspect ratio modes:
- `fit` (Default letterbox / original aspect ratio).
- `fill` (Stretch to fill entire display bounds).
- `cover` (Crop edges to fill 16:9 / 21:9 ultra-wide viewport).
- `16:9`, `4:3`, `21:9` (Explicit forced aspect overrides).

---

## 2. Advanced Audio & Subtitle Engine

### 2.1 Subtitle Synchronization & Custom Styling
- **Runtime Offset Tuning**: Expose `±100ms` micro-stepping controls (`-5000ms` to `+5000ms` total range).
- **Format Support**: Internal embedded tracks (`SubRip`, `ASS/SSA`, `VTT`, `DVB Subtitle`) and external file/URL injection (`.srt`, `.vtt`, `.ass`).
- **Styling Tokens**: Provide customizable font family, font size (14px - 48px), text color, outline stroke (width & color), background opacity, and vertical bottom margin.

### 2.2 Audio Track Switching & Lip-Sync Offset
- Support dynamic audio stream switching (Original, Mandarin, Commentary, Stereo, 5.1/7.1 Surround).
- Expose audio delay adjustment (`±50ms` micro-stepping) to fix A/V desync in non-standard IPTV feeds or transcode streams.
- Pitch correction preservation enabled when playback speed varies (`0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`, `3.0x`).

---

## 3. Danmaku (弹幕) Engine Integration (Animeko & Kazumi Pattern)

### 3.1 Architecture & Timeline Sync
- Superimpose a high-performance transparent canvas layer (`DanmakuOverlay`) directly above the video texture.
- Synchronize Danmaku timeline against `player.stream.position` in 16ms render ticks.
- Handle seek jumps by seeking the danmaku quad-tree / spatial partition index without UI lag.

### 3.2 Parser Formats
- Bilibili XML format (`<d p="time,mode,size,color,timestamp,pool,user,rowId">text</d>`).
- DPlayer JSON format (`[time, type, color, author, text]`).
- Kazumi / Animeko normalized comment entity.

### 3.3 Collision Prevention & User Filter Controls
- **Track Layout Algorithm**: Screen split into vertical lanes (10-32 lanes based on font size). Calculate collision avoidance before allocating lanes for rolling danmaku.
- **User Preference Controls**:
  - Opacity: `0%` (Hidden) to `100%`.
  - Display Area: `Top 25%`, `Top 50%`, `Top 75%`, `100% Full`.
  - Scroll Speed: `Slow (8s)`, `Normal (5s)`, `Fast (3s)`.
  - Keyword Filtering: Regex and exact match blacklist.
  - Type Filters: Toggle Rolling, Top Fixed, Bottom Fixed, Color danmaku.

---

## 4. TV D-Pad Focus & Remote Control Topology

### 4.1 Focus First Principles
- **Explicit Node Registration**: Every interactive element (Cards, Buttons, Sliders, List Tiles) MUST possess an explicit `FocusNode`.
- **Focus Visual Feedback**:
  - Focus ring with high-contrast accent color (`AppThemeColors.focusBorder`).
  - `1.05x` - `1.08x` smooth scale animation (`Curves.easeOutCubic`, 180ms).
  - Subtle drop shadow / glow elevation.

### 4.2 Standard Remote & Keypad Bindings
- `DPad Center / Enter / Space`: Toggle Play/Pause or Confirm Selection.
- `DPad Left / Right`: Short seek (-10s / +15s); Long press for continuous fast-forward.
- `DPad Up / Down`: In live mode, switch channel up/down; In VOD mode, adjust volume or brightness.
- `Menu Key (Remote)`: Open Quick Settings Drawer (Audio track, Subtitles, Quality, Danmaku, Speed, Ratio).
- `Back Key`: Close overlay / Exit fullscreen / Navigate back.
- `Number Keys (0-9)`: Display numeric jump overlay for live channel switching (e.g. typing `101` jumps directly to CCTV-1 HD).

---

## 5. Playback History & Smart State Restoration
- Persist playback timestamp every 5 seconds and upon `onDisposed()`.
- If remaining duration < 30 seconds or progress > 95%, mark episode as `completed`.
- Auto-resume prompt: "检测到上次播放至 24:18，[点击继续播放]".
