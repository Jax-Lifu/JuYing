---
name: iptv-live-engine
description: >-
  Guide for IPTV M3U/TXT parsing, CCTV dynamic HLS stream resolution, TVBox live formats,
  EPG XMLTV matching, IPv4/IPv6 dual-stack probing, catchup time-shift, and multi-route failover.
---

# IPTV Live Engine & Stream Resolver Skill

This skill defines the technical specification for parsing, validating, probing, scheduling, and playing live IPTV streams across IPv4 and IPv6 networks in JuYing.

---

## 1. Stream Format Compatibility Matrix

### 1.1 Extended M3U / M3U8 (`#EXTM3U`)
Parse all standard and vendor-specific attributes:
- `#EXTINF:-1 tvg-id="..." tvg-name="..." tvg-logo="..." group-title="央视频道" catchup="append" catchup-source="?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}", Channel Name`
- VLC / FongMi Headers:
  - `#EXTVLCOPT:http-user-agent=...`
  - `#EXTVLCOPT:http-referrer=...`
  - `#EXTHTTP:{"User-Agent":"...","Referer":"...","Origin":"...","Cookie":"..."}`
  - URL Query Suffix: `http://stream.m3u8;{User-Agent=Mozilla...&Referer=...}`

### 1.2 Grouped TXT Format
Support standard Chinese IPTV grouped text definitions:
```text
央视频道,#genre#
CCTV-1 综合 (1080P),http://[2409:8087:...]/cctv1.m3u8$线路1
CCTV-1 综合 (4K),http://112.17.x.x/cctv1_4k.m3u8$线路2
地方卫视,#genre#
浙江卫视,http://...
```

### 1.3 TVBox `lives` JSON Array
Support nested live subscriptions pointing to remote `.txt` / `.m3u` resources with EPG and channel logo overrides:
```json
{
  "name": "国内直播",
  "type": 0,
  "url": "https://live.fanmingming.com/tv/m3u/ipv6.m3u",
  "epg": "http://epg.51zmt.top:8000/api/diyp/?ch={name}&date={date}",
  "logo": "https://live.fanmingming.com/tv/{name}.png"
}
```

---

## 2. Dynamic CCTV & Official Stream Resolver

Do NOT hardcode temporary CDN tokenized streams. Implement an on-demand token resolver:
1. **Endpoint**: Query CNTV / VDN JSON API (`https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do?pid={channel_guid}`).
2. **Payload Resolution**: Extract dynamic HLS playlist with security auth token (e.g. `tsp`, `auth_key`, `wshc_tag`).
3. **Cache Policy**: Cache resolved HLS manifest URL for max 30 minutes; auto-refresh upon HTTP 403 response.

---

## 3. IPv4 & IPv6 Dual-Stack Probing (Guovin / iptv-api Pattern)

### 3.1 Network Probing on Startup (`NetworkProbeService`)
1. Dispatch lightweight async DNS & socket handshake to trusted IPv6 probes (e.g. `[2001:4860:4860::8888]:53`, `ipv6.test-ipv6.com`).
2. Detect IPv6 state: `Supported` vs `Unavailable`.
3. If IPv6 is available, elevate priority of IPv6-tagged multicast lines.
4. If IPv6 is unavailable, automatically filter or deprioritize IPv6 lines to prevent timeout stalls and black screens.

### 3.2 Lightweight Throughput & Latency Measuring
- **Master Playlist Inspection**: Fetch master `.m3u8` without downloading whole video; extract `#EXT-X-STREAM-INF:BANDWIDTH=...,RESOLUTION=1920x1080,FRAME-RATE=50`.
- **Sample Segment Probe**:
  - Sample the last 2 media chunks (`.ts` / `.m4s`).
  - Request first 128KB - 512KB with HTTP `Range` headers.
  - Calculate `Initial Byte Time (ms)` and `Throughput Speed (MiB/s)`.

### 3.3 Ad & Off-Air Stream Filtering
Filter invalid or placeholder streams matching:
- Stream duration $\le 90\text{s}$ with `#EXT-X-ENDLIST`.
- Playlist URIs containing: `no_signal`, `nosignal`, `no-signal`, `signal_offline`, `placeholder`, `cctv_off`, `/ad/`, `/ads/`.

---

## 4. Watchdog & 3-Second Circuit Breaker Auto-Failover

```
[Playing Line 1] ───(Stall > 3000ms OR HTTP 404/403/500)───> [Circuit Breaker Trips]
                                                                      │
                                                                      ▼
                                                      [Select Next Healthiest Route]
                                                                      │
                                                                      ▼
                                                      [Seamless Switch + Toast Tip]
```

- Watchdog polls playback clock every 500ms.
- If `player.stream.buffering` stays `true` for $\ge 3000\text{ms}$ or player throws network IO exception:
  1. Mark current line as degraded.
  2. Select next healthiest line from sorted candidates.
  3. Resume playback seamlessly at current timestamp.
  4. Display HUD notification: `已自动切换至 线路2 (1080P · 36ms)`.

---

## 5. EPG (Electronic Program Guide) & Catchup Time-Shift

### 5.1 EPG XMLTV Parsing & Fuzzy Matching
- Ingest `.xml` / `.xml.gz` EPG data (IPTV-org / 51zmt format).
- Normalize channel names (e.g. `CCTV1`, `CCTV-1`, `CCTV-1 综合`, `CCTV1HD` $\rightarrow$ canonical `cctv1`).
- Provide current program timeline progress indicator and upcoming schedule.

### 5.2 Catchup (回看) URL Interpolation
Support standard catchup patterns:
- `${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}`
- `${(b)timestamp}-${(e)timestamp}`
- `?playseek=20260821080000-20260821090000`
- Query EPG item timestamps and construct catchup URL when user clicks past programs.
