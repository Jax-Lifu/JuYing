---
name: lan-nas-streaming
description: >-
  Guide for Samba (SMBv2/v3), NFS (NFSv3/v4), WebDAV media streaming,
  Local Loopback HTTP Range Proxy, TMDB/NFO metadata scraping, and remote web configuration.
---

# LAN NAS Streaming & Remote Web Portal Skill

This skill provides technical architectures for integrating local network storage (Samba, NFS, WebDAV, Alist), high-performance seekable video streaming, and remote browser-based TV configuration.

---

## 1. Local Loopback HTTP Range Proxy (`127.0.0.1:9978`)

### 1.1 Architecture & Problem Definition
- **Problem**: Native video player engines (`media_kit` / `libmpv`) cannot directly parse proprietary SMB or NFS socket streams, and passing socket file descriptors across processes breaks random seeking, multi-track audio selection, and buffer caches.
- **Solution**:
  - Run an embedded lightweight HTTP server bound to `127.0.0.1:9978` (with port fallback `9978 - 9999`).
  - Player requests standard URL: `http://127.0.0.1:9978/proxy?id={stream_token}`.
  - Proxy intercepts incoming HTTP headers:
    - `Range: bytes=start-end` (e.g. `bytes=1048576-2097151`).
    - `User-Agent`, `Referer`, `Cookie`.
  - Proxy maps the request to underlying `libsmb2`, `libnfs`, or `WebDAV` client, performs random seek (`seek(start)`), reads chunks, and streams back a standard `HTTP/1.1 206 Partial Content` response with `Content-Range` and `Content-Length`.

```
[media_kit / libmpv] ───(HTTP Range: bytes=10M-20M)───> [127.0.0.1:9978 Micro Proxy]
                                                                  │
                                                        [Random Seek to 10MB]
                                                                  ▼
                                                      [SMBv3 / NFS / WebDAV NAS]
```

### 1.2 Benefits
- Instant seek performance without re-opening network sockets.
- Zero extra RAM buffer bloat.
- Full compatibility with external subtitle loading and multi-channel audio tracks.

---

## 2. Media Scraping & Local NFO Parsing

### 2.1 Filename Parser Regex (Animeko & Kazumi Pattern)
Extract metadata tokens from dirty video filenames:
- Title: Clean noise tokens (`[4K]`, `[1080P]`, `[HEVC]`, `[DDP5.1]`, `[SubtitleTeam]`, `[YYeTs]`).
- Season & Episode: Match `S01E05`, `EP05`, `第05集`, `05`, `E05`, `SP01`, `OVA`.
- Resolution & Codec: Match `2160p`, `4K`, `1080p`, `x265`, `HEVC`, `AV1`, `HDR10`, `DolbyVision`.

### 2.2 Local NFO & Artwork Hierarchy
Prioritize local filesystem assets before querying online scrapers:
1. `movie.nfo` or `{filename}.nfo` (Kodi / Emby / Jellyfin standard XML).
2. Local posters: `poster.jpg`, `cover.jpg`, `folder.jpg`.
3. Local backdrops: `fanart.jpg`, `backdrop.jpg`, `background.png`.
4. Local subtitles: `{filename}.zh-CN.srt`, `{filename}.ass`.

---

## 3. Remote Web Configuration Portal (FongMi Pattern)

### 3.1 Web Portal & QR Code Flow
1. Start lightweight web server listening on local LAN IP (e.g. `http://192.168.1.100:9978`).
2. Render QR code and URL on TV screen.
3. User opens URL in mobile or PC browser:
   - **Push TVBox Config**: Input or paste single/multi-warehouse subscription JSON/URL.
   - **Push IPTV Subscription**: Push M3U / TXT live stream playlists.
   - **Configure NAS Credentials**: Add SMB/NFS/WebDAV host, share, user, password.
   - **Push Video / DLNA Stream**: Send video URL directly to TV for instant playback.

### 3.2 Secure Credential Storage
All NAS credentials (passwords, SMB secrets, WebDAV tokens) MUST be stored strictly in platform secure storage (`flutter_secure_storage` / Keychain / KeyStore), never logged in plain text or synced across untrusted channels.
