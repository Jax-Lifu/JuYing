---
name: iptv-live-engine
description: >-
  Guide for IPTV M3U/TXT parsing, CCTV dynamic HLS stream resolution, TVBox live formats,
  EPG XMLTV matching, IPv4/IPv6 dual-stack probing, catchup time-shift, and multi-route failover.
---

# IPTV Live Engine & Stream Resolver Skill

This skill provides guidelines and patterns for parsing, validating, resolving, and scheduling live streams in JuYing.

## 1. Stream Format Compatibility
- **M3U / M3U8**:
  - Parse `#EXTINF` attributes: `tvg-id`, `tvg-name`, `tvg-logo`, `group-title`, `catchup`, `catchup-source`.
  - Parse FongMi / Kodi stream parameters: `#EXTVLCOPT:http-user-agent=...`, `#EXTHTTP:{"Referer":"..."}`, or URL suffix `;{User-Agent=...&Referer=...}`.
- **TXT / Grouped Format**:
  - Parse `Channel Name,URL` format lines with category headers (e.g. `央视频道,#genre#`).
- **TVBox Live JSON**:
  - Extract `lives` configurations and resolve nested remote `.m3u` or `.txt` URLs.

## 2. CCTV Official Stream Resolver
- Do NOT hardcode temporary HLS URLs.
- Dynamically query CNTV/VDN metadata endpoints (`vdn.apps.cntv.cn`) with valid channel GUID/EPG keys.
- Extract trusted HLS manifest URLs with time-limited security tokens.

## 3. IPv4 & IPv6 Dual-Stack Probing (Guovin/iptv-api Pattern)
- In China and various global ISPs, many live IPTV streams (especially 4K/8K multicast streams) are IPv6-only or IPv4-only.
- Implement an async network environment prober (`NetworkProbeService`) on app startup:
  - Test IPv6 connectivity.
  - If IPv6 is available, elevate priority of IPv6-tagged stream lines.
  - If IPv6 is not available, automatically hide or deprioritize IPv6-only streams to avoid black screens and long timeouts.

## 4. Multi-Route Speed Probing & Failover
- **Speed Score**: Background async HEAD/Range probes to compute: `Latency (ms)`, `Initial Byte Time`, `Bitrate Estimate`.
- **Circuit Breaker & Auto-Failover**:
  - If the active stream encounters buffering stall > 3000ms or 403/404/500 HTTP errors, immediately trigger auto-failover to the next healthy route.
  - Show subtle notification toast: `已自动切换至线路 2 (1080p · 42ms)`.

## 5. Catchup & Time-Shift (时移回看)
- Support `catchup-source` formatting templates:
  - `${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}`
  - `${(b)timestamp}-${(e)timestamp}`
  - Query EPG schedule and enable time-shift slider during live broadcasts.
