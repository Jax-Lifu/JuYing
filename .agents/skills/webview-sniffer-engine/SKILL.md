---
name: webview-sniffer-engine
description: >-
  Guide for headless WebView media sniffing, network request interception,
  Cloudflare / 5-second challenge penetration, media regex matching, and Cookie harvesting.
---

# WebView Sniffer Engine & Anti-Crawler Penetration Skill

This skill defines the technical architecture for extracting real playable media streams (`.m3u8`, `.mp4`, `.flv`, `.mpd`) from complex, obfuscated, or Cloudflare-protected web pages using a headless or semi-visible WebView component.

---

## 1. Sniffer Architecture & Request Interception (Kazumi & FongMi Pattern)

```
[Sniffing Request: Target Web Page URL]
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Headless WebView Controller                         │
│ 1. Inject Desktop / Mobile User-Agent               │
│ 2. Load Target URL in Isolated Context             │
│ 3. Intercept Network Requests (shouldIntercept)     │
└──────────────────┬──────────────────────────────────┘
                   │
    ┌──────────────┴───────────────────────────┐
    ▼                                          ▼
[Media URL Filter (Regex)]       [Challenge / Cloudflare Detected]
- \.m3u8(\?.*)?$                 - Turnstile / 5s Shield
- \.mp4(\?.*)?$                  - Open Mini Interactive Modal
- video/mp2t / mime-type         - User Solves Captcha -> Harvest Cookie
    │                                          │
    ▼                                          ▼
[Extract Stream URL + Headers]   [Resume Interception Flow]
```

### 1.1 Network Interception Rules
- Inspect all outbound resource requests:
  - Match URL extensions: `.m3u8`, `.mp4`, `.flv`, `.mpd`, `.m4s`.
  - Match response `Content-Type`: `application/vnd.apple.mpegurl`, `video/mp4`, `video/x-flv`, `application/x-mpegurl`.
- Filter out false positives:
  - Ad video URLs (length $< 15\text{s}$ or domain matching ad filter lists).
  - Tracking pixels and analytics beacons.

---

## 2. Dynamic Challenge & Anti-Crawler Handling

### 2.1 Headless to Interactive Escalation
1. Attempt headless background evaluation first (timeout: 10s).
2. If page detects headless environment or displays Cloudflare Turnstile / Captcha challenge:
   - Elevate WebView to a lightweight modal window for the user to complete the manual click verification.
   - Once verified, harvest updated `Cookie` jar and `User-Agent`.
   - Close modal and cache credentials for subsequent API calls.

### 2.2 JavaScript Injection Hooks
- Injected helper scripts hook `HTMLMediaElement.prototype.play` and `window.fetch` / `XMLHttpRequest` to capture dynamically generated blob URLs and tokenized playback manifests before they are obfuscated.

---

## 3. Resource Cleanup & Memory Safety
- WebView instances MUST be destroyed and garbage collected immediately after the target media stream is successfully resolved.
- Set a hard timeout of 12 seconds per sniffing session to prevent hung background browser processes.
