# Architecture

This document describes Cobrain's internal architecture for contributors and developers.

---

## High-Level Overview

Cobrain is a macOS SwiftUI application that runs as both a menu bar app and a windowed app. It captures screenshots of the frontmost window on a timer, describes them using an on-device vision language model, and stores the descriptions in a searchable SQLite database.

```
┌─────────────────────────────────────────────────────────────┐
│                     CobrainApp (SwiftUI)                    │
│              Window Scene + MenuBarExtra Scene              │
├─────────────────────────────────────────────────────────────┤
│                        MainView                             │
│   ┌──────┬──────────┬──────┬────────┬──────────┐           │
│   │ Home │ Timeline │ Chat │ Browse │ Settings │           │
│   └──────┴──────────┴──────┴────────┴──────────┘           │
├─────────────────────────────────────────────────────────────┤
│                    Service Layer                             │
│  CaptureScheduler (orchestrator)                            │
│  ├── ScreenCaptureService (ScreenCaptureKit)                │
│  ├── WindowMetadataService (Accessibility API)              │
│  ├── ContextDetectionService (NSWorkspace)                  │
│  ├── ChangeDetectionService (pixel comparison)              │
│  ├── ModelManager (MLXVLM inference)                        │
│  ├── DeduplicationService (SHA256 + LRU cache)              │
│  └── StorageManager (GRDB + SQLite + FTS5)                  │
│                                                              │
│  SummaryService (async background summarization)            │
│  AppSettings (UserDefaults singleton)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
cobrain/Sources/
├── App/
│   ├── CobrainApp.swift      # @main entry, window + menu bar scenes
│   └── DS.swift              # Design system tokens (colors, fonts, spacing)
├── Models/
│   ├── Fragment.swift        # Core data model + search result wrapper
│   ├── AppSettings.swift     # User preferences (Observable, UserDefaults)
│   └── AppCategory.swift     # App categorization by bundle ID
├── Services/
│   ├── CaptureScheduler.swift       # Pipeline orchestrator
│   ├── ScreenCaptureService.swift   # Screenshot capture (ScreenCaptureKit)
│   ├── WindowMetadataService.swift  # Window title + URL (AX API)
│   ├── ContextDetectionService.swift # Frontmost app detection
│   ├── ChangeDetectionService.swift  # Pixel-based change detection
│   ├── ModelManager.swift            # VLM lifecycle + inference
│   ├── DeduplicationService.swift    # Hash-based duplicate prevention
│   ├── StorageManager.swift          # SQLite + FTS5 database
│   └── SummaryService.swift          # Background fragment summarization
└── Features/
    ├── Search/       # HomeView (landing) + SearchResultsView
    ├── Chat/         # ChatView + ChatViewModel (RAG chat)
    ├── Timeline/     # TimelineView (day-based chronological)
    ├── Browser/      # BrowserView + BrowserViewModel (app-centric)
    ├── Settings/     # SettingsView (all preferences)
    └── Onboarding/   # OnboardingView (permissions setup)
```

---

## Services

### CaptureScheduler — Pipeline Orchestrator

The central coordinator. Runs on a `DispatchSourceTimer` (utility QoS) and orchestrates the full capture flow:

1. Check preconditions (capture enabled, not paused, accessibility granted)
2. Get frontmost app context (skip if excluded or self)
3. Capture screenshot via ScreenCaptureService
4. Read metadata via WindowMetadataService
5. Run change detection against previous capture
6. If changed: downsample, describe via ModelManager, dedup, save to StorageManager
7. If unchanged: exponential backoff (5s → 10s → 20s → 30s max)

Listens for system events:
- **App switch** → force capture (clear previous image)
- **Sleep/screen lock** → pause
- **Wake/unlock** → resume with delay

### ScreenCaptureService

Wraps ScreenCaptureKit to capture the frontmost window:
- Finds the largest on-screen window matching a given PID
- Captures at 2x scale (Retina) for better VLM accuracy
- `downsampleForVLM()` scales to max 1024px to limit inference cost
- Manages screen recording permission checks

### WindowMetadataService

Extracts window title and browser URL via the Accessibility API:
- **Title:** AXFocusedWindow → AXTitle attribute
- **URL extraction** (browsers only, three strategies):
  1. AXDocument attribute (cheapest)
  2. UI tree traversal (depth-limited to 6 levels) looking for address bar
  3. AppleScript fallback (Safari, Chrome, Arc, Brave)

### ChangeDetectionService

Prevents redundant VLM calls when the screen hasn't changed:
- Downsamples both images to 64x64 grayscale
- Counts pixels differing by >20 intensity units (noise tolerance)
- Returns fraction of changed pixels (0.0–1.0)
- Default threshold: 5% (configurable)

### DeduplicationService

Secondary filter that prevents duplicate fragment content:
- SHA256 hash of normalized text (lowercase, whitespace-collapsed)
- LRU cache of 50 recent entries (in-memory)
- Checks against bundleID + windowTitle for context-aware dedup

### ModelManager

Manages the on-device VLM lifecycle (MLXVLM):
- **States:** idle → downloading (with progress) → loading → ready / error
- **`describe(image:)`** — 2–3 sentence screenshot description (temperature 0.3)
- **`complete(system:user:)`** — Text completion for summaries (max 256 tokens)
- **`stream(system:user:)`** — Streaming response for chat (AsyncThrowingStream)
- Models hosted on Hugging Face (mlx-community), downloaded on first use

### StorageManager

GRDB.swift wrapper for SQLite with FTS5 full-text search:
- **Location:** `~/Library/Application Support/cobrain/brain.sqlite`
- **WAL mode**, NORMAL synchronous, 5s busy timeout
- **FTS5 virtual table** with Porter stemming + Unicode tokenization
- Auto-synced via SQL triggers on insert/update/delete
- BM25 ranking for search results with snippet extraction
- Handles retention-based purging and data deletion

### SummaryService

Background task that generates concise summaries:
- Runs every 120 seconds (10s initial delay)
- Fetches up to 20 unsummarized fragments (wordCount > 5)
- Calls ModelManager.complete() for each
- Updates the fragment's `summary` field in the database

---

## Data Flow

### Capture Pipeline

```
Timer (5-30s adaptive)
    │
    ▼
ContextDetectionService ──→ frontmost app (bundleID, PID)
    │
    ▼
ScreenCaptureService ──→ CGImage (2x Retina)
    │
    ▼
WindowMetadataService ──→ title, URL
    │
    ▼
ChangeDetectionService ──→ pixel diff vs previous
    │                         │
    │ (≥5% changed)           │ (<5% changed)
    ▼                         ▼
Downsample to 1024px       Back off timer
    │                      (skip VLM)
    ▼
ModelManager.describe() ──→ text description
    │
    ▼
DeduplicationService ──→ SHA256 check
    │
    ▼
StorageManager.saveFragment() ──→ SQLite + FTS5 index
```

### Chat Context Building

```
User query: "What was I reading about auth?"
    │
    ▼
Extract keywords: ["reading", "auth"]
    │
    ▼
FTS5 search per keyword (limit 5 each)
    +
App name matching ("auth" → no app match)
    +
Recent 10 fragments (always included)
    │
    ▼
Deduplicate by fragment ID
    │
    ▼
Build system prompt with ≤20 fragments
    │
    ▼
ModelManager.stream() ──→ real-time response
```

---

## Database Schema

```sql
CREATE TABLE fragments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    contentHash TEXT NOT NULL,
    focusedText TEXT,
    bundleIdentifier TEXT NOT NULL,
    appName TEXT NOT NULL,
    windowTitle TEXT,
    url TEXT,
    appCategory TEXT,
    capturedAt INTEGER NOT NULL,
    day TEXT NOT NULL,
    wordCount INTEGER DEFAULT 0,
    summary TEXT
);

-- Indexes
CREATE INDEX idx_fragments_day ON fragments(day);
CREATE INDEX idx_fragments_capturedAt ON fragments(capturedAt);
CREATE INDEX idx_fragments_contentHash ON fragments(contentHash);
CREATE INDEX idx_fragments_bundleIdentifier ON fragments(bundleIdentifier);
CREATE INDEX idx_fragments_appCategory ON fragments(appCategory);

-- FTS5 virtual table (auto-synced via triggers)
CREATE VIRTUAL TABLE fragments_fts USING fts5(
    content, windowTitle, appName, url,
    content='fragments',
    content_rowid='id',
    tokenize='porter unicode61'
);
```

---

## Design System (DS)

Centralized design tokens in `DS.swift`:

- **Accent color:** Amber/gold (adaptive light/dark)
- **Typography:** 5 levels (title, subtitle, body, caption, mono)
- **Spacing:** 7 increments (xxs=2 through xxl=28)
- **Corner radius:** 4 sizes (sm=5 through xl=12)
- **View modifiers:** `.dsCard()`, `.dsFragmentCard()`, `.dsKeyBadge()`

---

## Key Design Decisions

### Why unsandboxed?
The Accessibility API (AXUIElement) requires the app to run outside the macOS sandbox. This is needed to read window titles and browser URLs — metadata that makes fragments searchable and useful.

### Why on-device VLM?
Privacy. Screenshots contain sensitive content (code, messages, passwords). Processing them locally means nothing leaves the user's machine. The trade-off is higher CPU/GPU usage and model download size.

### Why FTS5 over vector search?
FTS5 with Porter stemming provides fast, accurate keyword search without requiring embedding models or additional dependencies. BM25 ranking produces good results for the kind of short-text fragments Cobrain stores.

### Why adaptive scheduling?
VLM inference is expensive. If the screen hasn't changed, there's no point running the model. Exponential backoff (5s → 30s) reduces CPU usage during idle periods while still capturing changes quickly.

### Why deferred summarization?
Running the VLM twice per capture (describe + summarize) would be too slow. Instead, SummaryService runs in the background every 120 seconds, summarizing fragments after the fact. This keeps capture latency low.

---

## Dependencies

| Dependency | Purpose | Source |
|------------|---------|--------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite wrapper + FTS5 | Swift Package |
| [MLXVLM](https://github.com/ml-explore/mlx-swift-lm) | On-device vision language model inference | Swift Package (branch: main) |
| [Sparkle](https://sparkle-project.org) | macOS auto-update framework | Swift Package |

### System Frameworks
- **ScreenCaptureKit** — Window screenshot capture
- **Accessibility** (ApplicationServices) — AXUIElement for window metadata
- **AppKit/SwiftUI** — UI framework
- **CryptoKit** — SHA256 hashing for deduplication

---

## Build System

Cobrain uses [Tuist](https://tuist.io) for project generation:

- `Project.swift` defines targets, dependencies, entitlements, and signing
- `Tuist/Package.swift` declares Swift Package dependencies
- `mise.toml` pins Tuist version (4.155.0)
- `Makefile` orchestrates the release pipeline (archive → export → DMG → notarize → upload)

---

## Threading Model

| Component | Thread | Mechanism |
|-----------|--------|-----------|
| CaptureScheduler | Background (utility QoS) | DispatchSourceTimer + DispatchQueue |
| ScreenCaptureService | Async | ScreenCaptureKit async API |
| ModelManager | Main actor | @MainActor + async/await |
| StorageManager | Caller's thread | GRDB's DatabasePool handles concurrency |
| SummaryService | Main actor | @MainActor + Task with sleep |
| UI (all views) | Main thread | SwiftUI @Observable |
