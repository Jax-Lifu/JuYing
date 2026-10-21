---
name: tvbox-spider-sandbox
description: >-
  Guide for TVBox config aggregation (JSON/DC/WebP/AES), CatVod Spider protocol,
  QuickJS sandboxed execution, identity vs candidate decoupling, CCTV official VOD adapter, and safe multi-source federated search.
---

# TVBox Spider Sandbox & Multi-Source Aggregation Skill

This skill defines the runtime architecture, sandbox security boundaries, Spider contracts, CCTV official VOD adapters, and federated search engine for TVBox configurations and rules.

---

## 1. TVBox Subscription & Configuration Specification

### 1.1 Supported Subscription Formats
1. **Standard Single Warehouse (`JSON`)**:
   - `spider`: Remote `.jar` or `.js` spider bundle URL.
   - `sites`: Array of source adapters (`[{key, name, type, api, searchable, quickSearch, filterable, ext, playerType, jar}]`).
   - `lives`: Live streaming subscriptions.
   - `parses`: Web sniffers & JSON parse APIs (`[{name, type, url, ext}]`).
   - `rules`: Regex request rewriting rules.
   - `doh`: DNS-over-HTTPS providers.
   - `flags`: Custom player flag mapping (`["youku", "qq", "bilibili", "alivod", "quark"]`).
2. **Multi-Warehouse (`dc` / `dc.txt` / `JSON`)**:
   - Array of `[{name: "饭太硬", url: "http://..."}, {name: "肥猫", url: "http://..."}]`.
3. **Encrypted / WebP / Base64 Obfuscation Unpacking**:
   - Extract base64 payload from WebP trailer or raw encrypted string.
   - Decrypt via AES-128-CBC / AES-128-ECB with standard TVBox magic keys (`2803...` / `2401...`) in memory.

---

## 2. CatVod Spider Protocol & QuickJS Sandboxed Engine

### 2.1 Spider Protocol Methods
Every TVBox Spider (JS / Dex) MUST implement the standard CatVod interface:

| Method | Signature | Description |
| :--- | :--- | :--- |
| `init(ext)` | `(ext: string \| object) -> void` | Initialize spider with external config parameters |
| `home(filter)` | `(filter: boolean) -> string` | Return category tree and recommendation feeds |
| `homeVod()` | `() -> string` | Return homepage spotlight videos |
| `category(tid, pg, filter, extend)` | `(tid: string, pg: string, filter: boolean, extend: object) -> string` | Fetch paginated category listings |
| `detail(id)` | `(id: string) -> string` | Fetch full media detail (episodes, play flags, cast, plot) |
| `search(key, quick, pg)` | `(key: string, quick: boolean, pg?: string) -> string` | Search catalog by keyword |
| `play(flag, id, vipFlags)` | `(flag: string, id: string, vipFlags: string[]) -> string` | Resolve playable stream URL or headers |
| `proxy(params)` | `(params: object) -> [code, contentType, streamBytes, headers]` | Intercept and proxy custom encrypted video streams |
| `action(action)` | `(action: string) -> string` | Handle custom UI actions (e.g. captcha verification) |
| `destroy()` | `() -> void` | Clean up memory and terminate background workers |

### 2.2 QuickJS Sandbox Security Boundary
All JavaScript spiders execute inside an isolated **QuickJS** VM context:
- **Strict Network Whitelist**: Spiders can ONLY initiate HTTP/HTTPS requests via the injected `http` / `fetch` bridge.
- **Filesystem Isolation**: Deny all direct OS filesystem access, shell execution, child processes, or native library loading.
- **Resource Constraints**:
  - Max memory limit: 64MB per spider instance.
  - Execution timeout: 8000ms max per spider call. Auto-terminate hung tasks.
  - Single-threaded worker isolation per spider instance.

---

## 3. CCTV Official VOD Catalog & Column Archive Adapter (央视片库点播)

The application provides a first-class, built-in adapter for the official **CCTV Program Archive (央视片库 / 优秀节目展播 / 栏目大全 `tv.cctv.com/yxg`)**:

```
[User Selects Category: 动画片 / 电视剧 / 纪录片 / 特别节目]
                             │
                             ▼
  [CNTV Album Catalog API: https://api.cntv.cn/list/getVideoAlbumList]
  Params: channelid=CHAL..., fc=动画片, sc=分类, area=地区, letter=A-Z, p=1, n=24
                             │
                             ▼
  [CNTV Episode List API: https://api.cntv.cn/NewVideo/getVideoListByAlbumIdNew]
  Params: id=album_id, serviceId=tvcctv, p=1, n=100
                             │
                             ▼
  [Dynamic HLS Stream Resolver: https://vdn.apps.cntv.cn/api/getHttpVideoInfo.do]
  Params: pid=video_guid, tz=-8, from=000news
                             │
                             ▼
       [Extract 1080P/4K High-Bitrate HLS Manifest & Play in JuYing]
```

### 3.1 Supported CCTV Catalog Classes
- **动画片 (Animation)**: `channelid=CHAL1460955899450127`, `fc=动画片`, Subcategories: 亲子、搞笑、冒险、动作、宠物、益智、历史、教育、经典、神话、童话、热血。
- **电视剧 (TV Drama)**: `channelid=CHAL1460955924871139`, `fc=电视剧`, Subcategories: 军旅、谍战、古装、悬疑、历史、都市、农村。
- **纪录片 (Documentary)**: `channelid=CHAL1460955853485115`, `fc=纪录片`, Subcategories: 人文、历史、军事、自然、地理、探索、科技。
- **栏目大全 (Columns)**: `https://api.cntv.cn/lanmu/getLanMuListByFilter` covering 综合、新闻、少儿、科教、戏曲、体育等全频道栏目点播。

---

## 4. Canonical Identity vs Playback Candidate Decoupling (Animeko Pattern)

```
                       ┌───────────────────────────────┐
                       │  Canonical MediaItem          │
                       │  (TMDB / Douban / Bangumi ID) │
                       │  Title: 庆余年 第二季         │
                       │  Poster, Year, Overview, Cast │
                       └──────────────┬────────────────┘
                                      │ 1:N
             ┌────────────────────────┼────────────────────────┐
             ▼                        ▼                        ▼
┌─────────────────────────┐ ┌───────────────────┐ ┌──────────────────────┐
│ PlaybackCandidate       │ │ PlaybackCandidate │ │ PlaybackCandidate    │
│ Source: 央视网官方片库  │ │ Source: 肥猫 (B)  │ │ Source: 阿里云盘     │
│ Flags: 1080P/4K 官方    │ │ Flags: 蓝光, VIP  │ │ Flags: 原画 4K 60FPS │
│ Episodes: 1 - 36        │ │ Episodes: 1 - 36  │ │ Episodes: 1 - 36     │
└─────────────────────────┘ └───────────────────┘ └──────────────────────┘
```

- **Domain Model**: Search results MUST NOT duplicate the canonical title. Multiple candidates from disparate spider sources aggregate under a single `MediaItem`.
- **Seamless Line Switching**: User selects an episode; JuYing automatically matches corresponding candidate episodes across all available sources.

---

## 5. Federated Multi-Source Search & Epoch Cancellation

```
User Input ──(Debounce 300ms)──> [New EpochId = N+1] ───> [Cancel Previous Tokens]
                                          │
                  ┌───────────────────────┼───────────────────────┐
                  ▼                       ▼                       ▼
           [Spider Site 1]         [CCTV 央视片库]         [Spider Site 3]
                  │                       │                       │
                  └───────────────────────┼───────────────────────┘
                                          │
                                          ▼
                      [StreamMerge & Deduplicate by Identity]
                                          │
                                          ▼
                               [Notify UI with Epoch N+1]
```

- **Debounce**: 300ms debounce before dispatching search queries.
- **Monotonic Epoch**: When a new search is initiated, cancel active `CancelToken`s and increment `searchEpochId`. Any incoming async response bearing an older `epochId` is discarded immediately.
- **Progressive Stream Update**: Search results stream to UI reactively as each individual source completes.
