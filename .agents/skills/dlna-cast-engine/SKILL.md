---
name: dlna-cast-engine
description: >-
  Guide for DLNA / UPnP multi-device media casting, DMC controller/sender,
  DMR receiver/player service, and AVTransport/RenderingControl protocol handling.
---

# DLNA Cast Engine & Multi-Device Streaming Skill

This skill defines the technical specification for discovering, controlling, and receiving UPnP/DLNA media streams across local network devices in JuYing.

---

## 1. Dual-Role Architecture (DMC & DMR)

JuYing operates in two distinct DLNA modes depending on the runtime device form factor:

```
┌─────────────────────────────────┐                ┌─────────────────────────────────┐
│ Mobile / PC (DMC Controller)    │                │ TV / Desktop (DMR Receiver)     │
│ 1. SSDP Device Discovery        │──(AVTransport)─>│ 1. SSDP Advertiser Daemon       │
│ 2. SetAVTransportURI            │──(HTTP Range)──>│ 2. Embedded Media Server (:9978)│
│ 3. Play / Pause / Seek / Volume │<─(State Events)─│ 3. Hardware Video Playback      │
└─────────────────────────────────┘                └─────────────────────────────────┘
```

### 1.1 Digital Media Controller (DMC - 发送端)
- **SSDP Discovery**: Broadcast UDP M-SEARCH to multicast address `239.255.255.250:1900` to discover active DLNA renderers (Smart TVs, TV Boxes, Kodi).
- **Service Binding**: Bind to `urn:schemas-upnp-org:service:AVTransport:1` and `urn:schemas-upnp-org:service:RenderingControl:1`.
- **Remote Commands**:
  - `SetAVTransportURI(CurrentURI, CurrentURIMetaData)`: Push playable stream.
  - `Play()`, `Pause()`, `Stop()`: Remote playback transport control.
  - `Seek(Unit="REL_TIME", Target="01:23:45")`: Seek position on the remote TV screen.
  - `SetVolume(DesiredVolume)`: Adjust remote audio level (0-100).

### 1.2 Digital Media Renderer (DMR - 接收端)
- **Background Daemon**: When JuYing runs on Windows or Android TV, advertise DMR service over SSDP (`urn:schemas-upnp-org:device:MediaRenderer:1`).
- **Stream Ingestion**:
  - When mobile phones (e.g. Bilibili, Tencent Video, iQIYI, or JuYing Mobile) cast to JuYing, intercept incoming `SetAVTransportURI`.
  - Pass the stream URL through JuYing's unified `media_kit` (libmpv) player.
  - Report playback status (playing, paused, current position, total duration) back to the sender via UPnP eventing.

---

## 2. Protected Streams & Loopback Proxy Bridging (FongMi Pattern)

- **Problem**: When casting cloud drive videos (Aliyun, Quark) or NAS streams (Samba, NFS) with custom HTTP headers or auth tokens, generic Smart TVs fail to play due to missing headers or invalid IP bindings.
- **Solution**:
  - DMC passes a local proxy URL: `http://{local_ip}:9978/cast?url={encoded_source}&token={id}`.
  - The embedded HTTP server on DMC proxies the stream, injecting required `Referer`, `User-Agent`, `Cookie`, and `Authorization` headers on the fly.

---

## 3. SSDP Network & Lifecycle Rules
- SSDP multicast operations MUST run in a dedicated background worker/isolate to prevent UI jank.
- Cleanly send `ssdp:byebye` packets when DMR service is stopped to remove ghost devices on the LAN.
