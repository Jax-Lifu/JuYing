---
name: cloud-drive-engine
description: >-
  Guide for multi-cloud drive search (pansou), OAuth token lifecycle & auto-refresh (CloudSaver, quark-auto-save),
  direct 302 streaming vs transcoding fallback, and WebDAV/Alist integration.
---

# Cloud Drive Engine & Storage Streaming Skill

This skill defines the technical specification for querying, authenticating, resolving direct stream URLs, and playing multimedia resources hosted on personal cloud drives (Aliyun Drive, Quark, 115, Baidu Netdisk, UC, Thunder, 123Pan) and WebDAV/Alist endpoints.

---

## 1. Multi-Cloud Drive Federated Search (pansou Pattern)

### 1.1 Supported Search Aggregators
Query distributed public cloud share search engines (e.g. PanSearch, Upso, PanSou, DaiGua, QianFan, ZhiZhen) across major cloud storage providers:
- 阿里云盘 (Aliyun Drive)
- 夸克网盘 (Quark Drive)
- 115 网盘 (115 Drive)
- 百度网盘 (Baidu Netdisk)
- UC 网盘 / 迅雷云盘 / 123 云盘

### 1.2 Resource Normalization Pipeline
When aggregating search results across plugins:
1. Extract share URL tokens (`share_id`, `folder_id`, `passcode`).
2. Deduplicate search results by canonical video titles and file sizes.
3. Classify resource format: `4K 原盘 (REMUX)`, `HEVC 1080P`, `TV Series Complete (全集)`, `Single Episode`.

---

## 2. Cloud Drive Authentication & Token Lifecycle (CloudSaver Pattern)

### 2.1 Supported Authentication Schemes
- **Aliyun Drive**: `refresh_token` exchange for `access_token` and `drive_id` via Open API / App API.
- **Quark Drive**: `Cookie` (`_UP_A4A_VT_`, `_UP_F_VT_`) extraction & auto-session keepalive.
- **115 Drive**: `UID`, `CID`, `SEID` Cookie pair and QR code fast login.
- **Baidu Netdisk / 123Pan / UC**: OAuth2 Token & Open API credentials.

### 2.2 Secure Storage & Auto-Refresh Rules
- All tokens, cookies, and passwords MUST be persisted solely in hardware-backed secure storage (`flutter_secure_storage`).
- **Proactive Token Refresh**:
  - Refresh tokens when expires_in $< 15\text{ minutes}$.
  - On HTTP `401 Unauthorized` during playback, pause stream, execute token refresh once, and resume without interrupting playback session.

---

## 3. Direct Streaming & Transcoding Fallback

```
[Cloud Drive Resource]
          │
          ▼
[Check User VIP & Bitrate Support]
          │
    ┌─────┴─────────────────────────┐
    ▼                               ▼
[Original Stream (4K / REMUX)]    [Transcoded Stream (1080P/720P)]
Direct 302 / Playback API         HLS / Smooth Transcode
(Highest audio/video fidelity)   (Saves mobile bandwidth)
```

### 3.1 Direct High-Bitrate 302 Extraction
- Request direct media download URL / video preview URL with valid drive authentication headers.
- If direct URL enforces strict IP binding or short expiry (e.g. Aliyun OSS download link), pipe through the Local Loopback Proxy (`127.0.0.1:9978`) to maintain persistent Range request support.

### 3.2 Alist & WebDAV Mount Integration
- Support mounting personal Alist server endpoints (`http://my-alist.local:5244/dav`).
- Auto-index cloud drive directory hierarchies as virtual media folders.
- Transparently stream media via WebDAV partial content chunking.
