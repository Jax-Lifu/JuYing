---
name: sync-storage-engine
description: >-
  Guide for multi-device WebDAV / Cloud storage data synchronization,
  conflict resolution (Last-Write-Wins), dirty tracking, and local database migrations.
---

# Sync Storage Engine & WebDAV Data Synchronization Skill

This skill defines the technical specification for synchronizing watch history, favorites, custom subscriptions, and settings across multi-platform JuYing clients via WebDAV (Nextcloud, Nutstore / 坚果云, Alist, self-hosted WebDAV).

---

## 1. WebDAV Sync Protocol Architecture (Kazumi Pattern)

```
┌─────────────────────────────────┐
│ Local JuYing SQLite / Isar DB   │
│ - Watch History (Progress / Ep) │
│ - Bookmarks / Favorites         │
│ - Subscriptions & Rules         │
└────────────────┬────────────────┘
                 │ (Diff & Dirty Flag Tracking)
                 ▼
┌─────────────────────────────────┐
│ WebDAV Sync Coordinator         │
│ - Conflict Resolution (LWW)     │
│ - Gzip Compressed JSON Payload  │
└────────────────┬────────────────┘
                 │ (HTTPS MKCOL / PUT / GET)
                 ▼
┌─────────────────────────────────┐
│ Remote WebDAV Server            │
│ Path: /JuYing/sync/data.json.gz │
└─────────────────────────────────┘
```

### 1.1 Remote File Hierarchy
The remote WebDAV folder structure MUST adhere to standard paths:
- `/JuYing/sync/v1/history.json.gz` (Watch history entries with millisecond timestamps).
- `/JuYing/sync/v1/favorites.json.gz` (Bookmarked media items and categories).
- `/JuYing/sync/v1/subscriptions.json.gz` (TVBox / IPTV custom subscription URLs).
- `/JuYing/sync/v1/settings.json.gz` (Non-credential UI and playback preferences).

---

## 2. Bidirectional Sync & Conflict Resolution

### 2.1 Last-Write-Wins (LWW) with Field-Level Merging
- Every syncable entity MUST contain:
  - `entityId`: Unique identifier (e.g. `tmdb_movie_12345` or `siteKey_vodId`).
  - `updatedAt`: Monotonic epoch timestamp in milliseconds.
  - `isDeleted`: Boolean tombstone flag for soft deletion sync.
- **Merge Strategy**:
  1. Fetch remote manifest with `ETag` / `Last-Modified`.
  2. If local `updatedAt > remote.updatedAt`, local wins and marks remote for update.
  3. If `remote.updatedAt > local.updatedAt`, remote overwrites local entry.
  4. For playback progress on the same episode, prioritize the record with larger `progressTimestamp` unless the newer record explicitly started from episode 0.

### 2.2 Periodic & Event-Driven Sync Triggers
- **On App Launch**: Background non-blocking pull to sync latest cloud progress.
- **On Playback Finish / Exit**: Debounced push (delay 3s) to commit updated watch position.
- **Manual Sync**: User clicks "立即同步" button in settings.

---

## 3. Security & Network Efficiency
- **Credential Storage**: WebDAV URL, username, and app password MUST be encrypted with `flutter_secure_storage`.
- **Payload Compression**: All payloads MUST be serialized to JSON and compressed using Gzip before transmission to minimize bandwidth consumption on mobile networks.
- **Atomic File Writes**: Remote upload uses temporary write followed by rename: `PUT /sync/history.tmp` $\rightarrow$ `MOVE /sync/history.json.gz`.
