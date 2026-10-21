---
name: offline-download-manager
description: >-
  Guide for multi-threaded M3U8 TS segment downloading, AES-128 decryption,
  FFmpeg MP4 remuxing, cloud drive range download, and background task lifecycle.
---

# Offline Download Manager & Media Caching Skill

This skill defines the technical specification for downloading, decrypting, and assembling HLS/M3U8 streams and direct HTTP video streams for offline playback in JuYing.

---

## 1. M3U8 Multi-Threaded Chunk Downloader (Kazumi Pattern)

```
[M3U8 Master / Media Playlist]
             │
             ├─ [Parse #EXT-X-KEY: AES-128, URI="key.bin", IV=0x...]
             ├─ [Extract 1..N Segment URLs (.ts / .m4s)]
             │
             ▼
[Thread Pool: 8 - 16 Workers]
┌────────────┬────────────┬────────────┬────────────┐
│ Worker 1   │ Worker 2   │ Worker 3   │ Worker 4   │
│ Chunk 0..9 │ Chunk 10.. │ Chunk 20.. │ Chunk 30.. │
└────────────┴────────────┴────────────┴────────────┘
             │ (Download & In-Memory AES Decrypt)
             ▼
[Local Temp Directory: .cache/downloading/{taskId}/]
             │
             ▼
[Remuxer & Concatenator: TS -> Standalone .mp4]
             │
             ▼
[Atomic Move to: /JuYing/Downloads/{Title}/EP01.mp4]
```

### 1.1 Download Execution Pipeline
1. **Playlist Parsing**: Fetch media playlist, resolve relative segment URLs, and fetch cryptographic keys if `#EXT-X-KEY` (AES-128 / SAMPLE-AES) is present.
2. **Chunk Scheduling**: Maintain a persistent queue of chunks with retry backoff (max 3 retries per chunk).
3. **Decryption on the Fly**: Decrypt encrypted TS blocks before writing to local disk chunks to prevent corrupted disk blocks.
4. **Remuxing & Atomic Move**:
   - Merge ordered chunks and remux container from MPEG-TS into standard MP4 (`copy` video/audio codecs without lossy re-encoding).
   - Atomically rename temporary target to the final destination directory.

---

## 2. Cloud Drive & Direct Range Downloading

- **HTTP Range Chunks**: For single direct video files (Aliyun, 115, Quark, WebDAV), split download task into 4-8 concurrent byte-range workers (`Range: bytes=0-10485759`, etc.).
- **Token Refresh During Download**: If any worker receives HTTP `401 / 403` due to temporary URL expiration, pause download queue, refresh drive token, obtain updated direct URL, and resume downloading seamlessly.

---

## 3. Background Execution & Storage Guarding

- **Mobile Background Service**: On Android / iOS, register foreground service with ongoing notification to prevent OS battery optimization killer from terminating active downloads.
- **Disk Space Check**: Check free disk space before initiating download. If available storage $< 2\times$ estimated video size, abort with clear warning prompt.
- **Task Lifecycle**: Support Pause, Resume, Cancel, and Batch Delete operations.
