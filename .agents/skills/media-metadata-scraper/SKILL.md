---
name: media-metadata-scraper
description: >-
  Guide for TMDB / Douban / Bangumi metadata scraping, parallel prefetch with Generation Token guarding (WebHomeTV2),
  dirty title regex cleaning, and season/episode mapping.
---

# Media Metadata Scraper & Enrichment Skill

This skill defines the technical specification for scraping, cleaning, indexing, caching, and enriching media artwork, episode lists, and cast details across TMDB, Douban, and Bangumi.

---

## 1. Multi-Provider Scraping & Aggregation

### 1.1 Supported Metadata Providers
- **TMDB (The Movie Database)**: Primary global movie and TV series metadata provider (high-resolution posters, backdrops, ratings, episode air dates, cast & crew).
- **Douban (豆瓣)**: Primary Chinese film and TV show metadata provider (Chinese localized synopses, Douban score, popular tags).
- **Bangumi (番组计划)**: Primary anime and ACG metadata provider (episodes, seasons, character mappings, broadcast calendar).

---

## 2. TMDB Detail & Crawler Parallel Prefetch Architecture (WebHomeTV2 Pattern)

```
VideoDetailActivity.init()
       ├─ [TMDB Prefetch Slot] ────────(Async TMDB Detail API)────────┐
       │   Token: generationId = N+1                                  │
       │   Key: normalize(mediaType) + tmdbId                         │
       │                                                              ▼
       └─ [Spider Crawler Detail] ─────(Async Spider detailContent)─> [Merge Slot]
           Site: siteKey, ID: vodId                                   │
                                                                      ▼
                                                      [Enrich Real Vod Metadata]
                                                      [Notify UI & Reveal]
```

### 2.1 Parallel Execution Principles
- **No Extra Delay**: When entering a detail page with a known `TmdbItem`, dispatch the TMDB core detail request in parallel with the Spider crawler `detailContent()` request.
- **Single Subject Authority**: The Spider crawler `Vod` remains the sole authority for playable episode flags, stream URLs, and station identities. TMDB only enriches poster, backdrop, overview, ratings, cast, and episode titles.

### 2.2 Generation Token & `VodEventGuard`
- **Race Condition Prevention**: Increment `loadGeneration` whenever a new detail page is requested.
- **Stale Discard**: If the user quickly navigates back or jumps to another title before an async TMDB or Spider response resolves, the token mismatch triggers an immediate discard, preventing stale metadata from contaminating the new page.

---

## 3. Title & Episode Regex Normalization (Animeko & Kazumi Pattern)

### 3.1 Title Noise Stripping
Dirty release titles often contain codec, release group, and formatting noise. Clean titles using regex pipelines:
```dart
String cleanMediaTitle(String raw) {
  return raw
      .replaceAll(RegExp(r'\[.*?\]|【.*?】|\(.*?\)|（.*?）'), ' ')
      .replaceAll(RegExp(r'(4K|2160[pP]|1080[pP]|720[pP]|HD|BD|REMUX|WEB-DL|HEVC|x265|x264|H\.265|AAC|DDP\d\.\d)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
```

### 3.2 Season & Episode Number Matching
- **Episode Numbering (`EpisodeSort`)**:
  - `S01E05` / `s1e5` $\rightarrow$ Season 1, Episode 5
  - `第05集` / `第5话` $\rightarrow$ Episode 5
  - `EP05` / `E05` / `[05]` $\rightarrow$ Episode 5
  - `23.5` / `SP01` / `OVA01` $\rightarrow$ Special / OVA Episode

---

## 4. Multi-Tiered Metadata Caching Strategy

```
[UI / Detail Request]
          │
          ▼
[L1 Memory Cache] (LRU 100 items - instant render)
          │ (Miss)
          ▼
[L2 Local SQLite / Hive Cache] (Indexed by providerId, TTL: 7 days)
          │ (Miss)
          ▼
[L3 Remote API Fetch] (TMDB / Douban / Bangumi with Retry & Backoff)
```
