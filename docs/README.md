# Cobrain

**Your memory, searchable.**

Cobrain is a macOS app that quietly captures what you see on screen, describes it using an on-device AI model, and stores it in a searchable local database. Nothing ever leaves your Mac.

Think of it as a personal search engine for everything you've done on your computer.

---

## How It Works

1. **Capture** — Every few seconds, Cobrain screenshots the frontmost window and reads its title and URL.
2. **Understand** — An on-device vision language model (VLM) generates a 2–3 sentence description of what's on screen.
3. **Store** — The description, app name, window title, URL, timestamp, and screenshot are saved locally. Text goes into a SQLite database with full-text search; screenshots are saved as JPEGs organized by day.

You can then search, browse, chat with, replay, or timeline-view your captured history.

---

## Features

### Search
Full-text search across all captured fragments. Results are ranked by relevance (BM25) with highlighted snippets. Filter by app using source chips on the home screen.

### Chat
Ask natural-language questions about your activity. Cobrain retrieves relevant fragments and uses the on-device model to answer based only on what it has captured. Responses stream in real-time.

**Example questions:**
- "What was I working on in VS Code yesterday?"
- "What was that Slack thread about authentication?"
- "Summarize my browsing from this morning"

### Timeline
Browse your day chronologically. Fragments are grouped into time blocks (morning, afternoon, evening, night) with app icons and summaries. Expand any entry to see its saved screenshot thumbnail. Navigate between days.

### Replay
Play back your day as a visual slideshow of saved screenshots. Controls include:
- **Play/Pause** with automatic advancement
- **Frame-by-frame** stepping (forward/back)
- **Scrub slider** to jump to any point in the day
- **Speed control** (0.5x, 1x, 2x, 4x)
- **Metadata overlay** showing the app name, window title, and timestamp for each frame

Navigate between days to replay any day in your history.

### Browse
Explore captured content organized by application. See which apps you've used most, with fragment counts and day-based grouping.

### Menu Bar
Quick access from the menu bar. See capture status (active/paused), today's fragment count, and jump to search.

---

## Privacy

Cobrain is built privacy-first:

- **100% on-device** — The AI model runs locally on your Mac. No data is sent to any server.
- **Screenshots saved locally** — Screenshots are stored as JPEG files on your Mac at `~/Library/Application Support/cobrain/screenshots/`, organized by day. They never leave your device.
- **Local database** — All text data lives in `~/Library/Application Support/cobrain/brain.sqlite`.
- **App exclusions** — Sensitive apps (1Password, Keychain Access) are excluded by default. Add any app you want.
- **Data retention** — Configure how long data is kept (30–365 days, default 90). Delete everything instantly from Settings.
- **Unsandboxed for a reason** — The app needs Accessibility API access to read window titles and browser URLs. It does not read text content from apps.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (for on-device ML inference)
- ~0.5–4.6 GB disk space for the AI model (depends on model choice)

---

## Installation

### Homebrew (recommended)
```bash
brew install --cask cobrain
```

### Manual
Download the latest DMG from [GitHub Releases](https://github.com/WeAreOutliers/cobrain/releases), open it, and drag Cobrain to Applications.

---

## Getting Started

1. **Launch Cobrain** — It appears in your menu bar.
2. **Grant permissions** — The onboarding flow asks for:
   - **Accessibility** — To read window titles and browser URLs
   - **Screen Recording** — To capture screenshots of the frontmost window
3. **Choose a model** — Pick a VLM in Settings. Smaller models are faster; larger ones are more accurate.
4. **Let it run** — Cobrain captures in the background. Search your memory anytime.

---

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Capture frequency | 5 seconds | How often to capture (2–30s) |
| Change threshold | 5% | Minimum pixel change to trigger a new capture |
| Model | Qwen 3 VL 4B | On-device VLM for describing screenshots |
| Excluded apps | 1Password, Keychain | Apps that are never captured |
| Retention | 90 days | How long fragments are kept before auto-deletion |
| Theme | System | Light, dark, or follow system |
| Auto-update | On | Check for updates via Sparkle |

---

## Supported AI Models

| Model | Size | Notes |
|-------|------|-------|
| Qwen 3 VL 2B | ~1.3 GB | Fast, good quality |
| **Qwen 3 VL 4B** | **~2.5 GB** | **Recommended — best balance** |
| Qwen 2.5 VL 3B | ~2.0 GB | Previous generation |
| Qwen 2.5 VL 7B | ~4.6 GB | Most accurate, slowest |
| Gemma 3 4B | ~2.8 GB | Google's model |
| SmolVLM 500M | ~0.5 GB | Smallest, fastest |
| SmolVLM 2.2B | ~1.5 GB | Small but capable |

All models run locally via [MLX](https://github.com/ml-explore/mlx) on Apple Silicon. Models are downloaded from Hugging Face on first use.

---

## Architecture Overview

```
┌─────────────────────────────────┐
│        Cobrain (SwiftUI)        │
│   Menu Bar + Window UI          │
├─────────────────────────────────┤
│  Home │ Search │ Timeline │ ... │
├─────────────────────────────────┤
│        StorageManager           │
│     SQLite + FTS5 Search        │
├─────────────────────────────────┤
│       CaptureScheduler          │
│  (adaptive timer, orchestrator) │
├────┬────┬─────┬────┬────┬───────┤
│ Screen │ Win  │ VLM │ Change │  │
│Capture │Meta  │Model│Detect  │  │
│  Kit   │ AX   │ MLX │ Pixel  │  │
└────┴────┴─────┴────┴────┴───────┘
```

### Capture Pipeline

```
Timer fires (every 5–30s, adaptive)
  → Detect frontmost app (skip if excluded or self)
  → Capture window screenshot (ScreenCaptureKit, 2x Retina)
  → Read window metadata (Accessibility API: title, URL)
  → Compare to previous capture (64x64 pixel diff)
  → If <5% change: back off timer, skip
  → If changed: downsample to 1024px, run VLM
  → Check deduplication (SHA256 hash)
  → Save screenshot to disk as JPEG (70% quality, organized by day)
  → Save fragment + image path to SQLite + FTS5 index
```

### Adaptive Scheduling

The capture interval adjusts automatically:
- Starts at the configured base interval (default 5s)
- Doubles on each consecutive unchanged screen (5s → 10s → 20s → 30s max)
- Resets to base interval when a change is detected or the user switches apps
- Pauses during sleep/screen lock, resumes on wake

---

## Data Model

Each captured moment is stored as a **Fragment**:

| Field | Description |
|-------|-------------|
| `content` | VLM-generated description of what was on screen |
| `appName` | Name of the frontmost application |
| `bundleIdentifier` | App's bundle ID (e.g., `com.google.Chrome`) |
| `windowTitle` | Window or tab title |
| `url` | Browser URL (if applicable) |
| `appCategory` | Automatic category: code, browsing, communication, email, work, design |
| `capturedAt` | Unix timestamp |
| `day` | Date string (YYYY-MM-DD) for grouping |
| `summary` | 1–2 sentence summary (generated asynchronously) |
| `imagePath` | Relative path to the saved screenshot JPEG (e.g., `2026-04-01/1711929600.jpg`) |

Fragments are indexed with SQLite FTS5 using Porter stemming and Unicode tokenization for fast, typo-tolerant search.

---

## App Categories

Cobrain automatically categorizes apps:

| Category | Apps |
|----------|------|
| Code | Xcode, VS Code, Cursor, JetBrains IDEs, Terminal, iTerm2, Warp |
| Browsing | Safari, Chrome, Arc, Firefox, Brave |
| Communication | Slack, Teams, Discord, Telegram |
| Email | Mail, Outlook |
| Work | Linear, Jira, Notion |
| Design | Figma, Sketch |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+K | Focus search bar |

---

## Storage

- **Database location:** `~/Library/Application Support/cobrain/brain.sqlite`
- **Screenshots location:** `~/Library/Application Support/cobrain/screenshots/{YYYY-MM-DD}/`
- **Format:** SQLite with WAL mode for concurrent reads/writes; screenshots as JPEG (~100–300 KB each)
- **Auto-cleanup:** Fragments and their associated screenshots older than the retention period are purged automatically
- **Manual cleanup:** Delete all data from Settings

---

## Auto-Updates

Cobrain uses [Sparkle](https://sparkle-project.org) for automatic updates. The update feed is hosted on GitHub Pages. You can check for updates manually from Settings or the About section.

---

## Building from Source

### Prerequisites
- macOS 14.0+
- Xcode 15+
- [mise](https://mise.jdx.dev) (for Tuist version management)

### Setup
```bash
# Install dependencies and generate Xcode project
mise exec -- tuist install
mise exec -- tuist generate

# Open workspace
open cobrain.xcworkspace
```

### Build & Run
```bash
# Build
xcodebuild -workspace cobrain.xcworkspace -scheme cobrain -configuration Debug build

# Run
open $(xcodebuild -workspace cobrain.xcworkspace -scheme cobrain \
  -configuration Debug -showBuildSettings 2>/dev/null \
  | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/cobrain.app
```

### Release
```bash
make release  # Full pipeline: generate → archive → export → DMG → notarize → appcast → upload
```

Individual steps: `make generate`, `make archive`, `make export`, `make dmg`, `make notarize`, `make appcast`, `make upload`.

---

## License

See [LICENSE](../LICENSE) for details.

---

## Links

- [GitHub](https://github.com/WeAreOutliers/cobrain)
- [Releases](https://github.com/WeAreOutliers/cobrain/releases)
- [Homebrew Cask](https://github.com/WeAreOutliers/cobrain/tree/main/Casks)
