---
name: lan-nas-streaming
description: >-
  Guide for Samba (SMBv2/v3), NFS (NFSv3/v4), WebDAV media streaming,
  Local Loopback HTTP Range Proxy, TMDB/NFO metadata scraping, and remote web configuration.
---

# LAN NAS Streaming & Remote Web Portal Skill

This skill defines the architecture for integrating local network storage (Samba/NFS/WebDAV), high-performance seekable streaming, and remote browser-based configuration.

## 1. Local Loopback HTTP Range Proxy (127.0.0.1)
- **Problem**: Native video player engines (media_kit/libmpv) cannot directly parse proprietary SMB/NFS socket streams, leading to seek latency or buffer starvation.
- **Solution**:
  - Run an embedded lightweight HTTP server bound to `127.0.0.1:[random_port]`.
  - When the player requests `http://127.0.0.1:port/stream/{token}`, the proxy intercepts HTTP `Range: bytes=start-end` headers.
  - Proxy delegates the seek and read operations to `libsmb2` or `libnfs` and returns a standard `206 Partial Content` response.
  - **Outcome**: Millisecond-level seek, zero RAM bloat, full support for multi-track audio and external subtitles.

## 2. Media Scraping & NFO Parsing
- **Filename Parser**: Extract title, season/episode (`S01E01`, `EP01`), resolution (`4K`, `1080p`), release year.
- **Local Metadata**: Prioritize adjacent `.nfo` files, `poster.jpg`, `fanart.jpg`.
- **Online Scraping**: Optional fallback to TMDB / Douban public APIs for posters and episode overviews.

## 3. Remote Web Configuration Portal (FongMi Pattern)
- **Problem**: Typing long subscription URLs on TV boxes using a remote control is tedious and error-prone.
- **Solution**:
  - Expose a built-in web portal (e.g. `http://192.168.x.x:9978`).
  - Display a QR code on the TV screen.
  - User can open the URL from phone/PC browser to:
    - Push IPTV M3U / TXT links.
    - Push TVBox subscription JSON.
    - Configure SMB/NFS NAS credentials.
    - Push single video streams directly to the TV screen.
