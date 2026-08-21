---
name: tvbox-spider-sandbox
description: >-
  Guide for TVBox config aggregation (JSON/XML/CMS/CatVod Spider), QuickJS sandboxed execution,
  identity vs candidate separation, and safe multi-source federated search.
---

# TVBox Spider Sandbox & Multi-Source Aggregation Skill

This skill defines the runtime architecture, sandboxing mechanisms, and query orchestration for TVBox configurations and custom spider rules.

## 1. Identity vs Candidate Architecture (Animeko Pattern)
- **MediaItem (Identity Layer)**: Represents the canonical media work (Title, Original Title, Poster, Year, Category, Cast, Overview).
- **PlaybackCandidate (Candidate Layer)**: Represents a specific playable stream from a specific source adapter (CCTV, TVBox Site A, TVBox Site B), containing routes, resolutions, headers, and episode indices.
- **Benefits**: Eliminates duplicate items in search results; lets user seamlessly switch between sources on the media detail page.

## 2. Sandboxed Spider Execution (QuickJS Engine)
- **Engine**: Embed **QuickJS** (via C-FFI / `flutter_js`) on all platforms.
- **Sandbox Security Boundary**:
  - Restrict network requests strictly to HTTP/HTTPS fetch APIs.
  - Deny arbitrary local filesystem access, process execution, or native shell commands.
  - Set execution timeouts (e.g. max 8s per spider call) to prevent infinite loops.
- **Spider Contract**:
  - `init(ext)`: Initialize spider with configuration string.
  - `home(filter)`: Return categories and homepage recommendations.
  - `category(tid, pg, filter, extend)`: Paginated category browse.
  - `detail(id)`: Fetch episode lists and play flags.
  - `search(key, quick)`: Query keyword results.
  - `play(flag, id, flags)`: Resolve final playable URL / header descriptors.

## 3. Federated Search Cancellation & Epoch Control
- When user types in the search bar:
  - Apply 300ms debounce.
  - Generate a monotonic `searchEpochId` (or cancel previous `CancelToken`s).
  - Dispatch concurrent queries across all active sources.
  - Ignore responses matching older epochs to prevent slow results from overwriting newer search results.
