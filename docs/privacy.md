# Privacy Policy

**Last updated: April 2026**

Cobrain is designed with privacy as a core principle. Your data never leaves your Mac.

---

## What Cobrain Captures

When capture is enabled, Cobrain periodically:

1. **Screenshots the frontmost window** — Using macOS ScreenCaptureKit. The screenshot is processed in memory and immediately discarded. It is never saved to disk.
2. **Reads window metadata** — Using the Accessibility API, Cobrain reads the window title and browser URL of the frontmost app. It does not read text content from within apps.
3. **Generates a text description** — An on-device AI model (running entirely on your Mac) describes what was visible in the screenshot in 2–3 sentences.
4. **Stores the description** — The text description, along with the app name, window title, URL, and timestamp, is saved to a local SQLite database.

**What is NOT captured or stored:**
- Screenshots or images of any kind
- Text content from within applications (clipboard, document text, etc.)
- Keystrokes or input
- Audio or video
- Any data from excluded apps

---

## Where Data Is Stored

All data is stored locally in:

```
~/Library/Application Support/cobrain/brain.sqlite
```

This is a standard SQLite database on your Mac's filesystem. No data is stored in the cloud, synced to external services, or transmitted over the network.

---

## Network Usage

Cobrain makes network requests only for:

1. **Model download** — When you first select an AI model, it is downloaded from Hugging Face (a public model repository). This is a one-time download per model.
2. **Update checks** — Cobrain checks for app updates via Sparkle (an open-source macOS update framework). The update feed is hosted on GitHub Pages.

Cobrain does **not** send any captured data, analytics, telemetry, or usage information over the network.

---

## AI Processing

The vision language model runs **entirely on your Mac** using Apple's MLX framework (optimized for Apple Silicon). No screenshot or description is sent to any external AI service. The model files are stored locally after download.

---

## Permissions Required

| Permission | Why | What It Accesses |
|------------|-----|------------------|
| **Accessibility** | To read window titles and browser URLs | AXUIElement attributes (title, document URL) |
| **Screen Recording** | To capture screenshots of the frontmost window | ScreenCaptureKit window capture |

These permissions are requested during onboarding and can be revoked at any time in System Settings > Privacy & Security.

---

## Excluded Apps

By default, Cobrain excludes:

- **1Password** (com.1password.1password)
- **Keychain Access** (com.apple.keychainaccess)

You can add or remove app exclusions in Settings. When an app is excluded, Cobrain skips capture entirely when that app is in the foreground — no screenshot is taken, no metadata is read, and no data is stored.

---

## Data Retention

- **Default retention:** 90 days
- **Configurable:** 30, 60, 90, 180, or 365 days
- **Manual deletion:** You can delete all captured data instantly from Settings
- **Automatic cleanup:** Fragments older than the retention period are purged automatically

---

## Your Controls

You have full control over Cobrain's behavior:

- **Pause/resume capture** at any time from Settings or the menu bar
- **Exclude any app** from being captured
- **Adjust capture frequency** (2–30 seconds)
- **Set data retention** period
- **Delete all data** with one click
- **Uninstall** removes the app; delete `~/Library/Application Support/cobrain/` to remove all data

---

## Open Source

Cobrain's source code is publicly available at [github.com/WeAreOutliers/cobrain](https://github.com/WeAreOutliers/cobrain). You can audit exactly what the app does.
