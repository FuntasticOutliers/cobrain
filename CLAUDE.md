# Cobrain — Claude Code Guidelines

## Build & Run (Development)

After making any code change, build and restart:

1. Kill the running app: `pkill -x cobrain`
2. Build: `xcodebuild -workspace cobrain.xcworkspace -scheme cobrain -configuration Debug build`
3. Launch: `open $(xcodebuild -workspace cobrain.xcworkspace -scheme cobrain -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/cobrain.app`

## Project Setup

This is a Tuist project. To regenerate after changing `Project.swift` or `Tuist/Package.swift`:

```
mise exec -- tuist install
mise exec -- tuist generate
```

## Release Pipeline

Full release: `make release` (runs all steps below in order)

Individual steps:
- `make generate` — install deps + generate Xcode project
- `make archive` — build xcarchive with Developer ID signing
- `make export` — export .app from archive
- `make dmg` — package as DMG with drag-to-Applications
- `make notarize` — submit to Apple notarization + staple
- `make appcast` — generate Sparkle appcast.xml
- `make upload` — create GitHub release with DMG

## Architecture

- macOS SwiftUI app (unsandboxed — required for Accessibility API metadata reads)
- Tuist build system
- GRDB.swift for SQLite + FTS5 full-text search
- ScreenCaptureKit for capturing screenshots of the frontmost window
- Accessibility API (AXUIElement) for window metadata (title, browser URL) — not for text capture
- On-device VLM (Qwen2.5-VL via MLXVLM) to describe screenshot content as natural language
- Menu bar app with full window UI
- Sparkle for auto-updates (feed hosted on GitHub Pages)

## Key Directories

- `Sources/App/` — entry point, design system
- `Sources/Models/` — data models (Fragment, AppSettings, AppCategory)
- `Sources/Services/` — core services (ScreenCapture, CaptureScheduler, ModelManager, WindowMetadata, ContextDetection, Storage, Deduplication, Summary)
- `Sources/Features/` — UI screens (Home, Search, Chat, Timeline, Browse, Settings, Onboarding)
