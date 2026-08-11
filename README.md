# Kinema

**Kinema** is a modern, cross-platform video player for **iOS**, **iPadOS**, **macOS**, and **tvOS**, inspired by [IINA](https://github.com/iina/iina) and powered by **libmpv**.

> κίνημα — motion, cinema

## Features

- Broad format support via libmpv / FFmpeg (H.264, H.265, AV1, VP9, MKV, and more)
- Unified SwiftUI interface across Apple platforms
- Subtitles: auto-match, manual load, Gestdown online TV search, styling
- Playlists (repeat / shuffle), chapters, A–B loop, A/V track selection
- Playback history with resume (SwiftData)
- System Now Playing / Lock Screen controls (where available)
- Video filters, fit / zoom / rotate, gesture controls, keyboard shortcuts
- `kinema://` deep links and Share Extension
- macOS: `kinema-cli`, Music Mode, yt-dlp online media support

## Requirements

- macOS 14+ (development)
- **Xcode 16+**
- Swift 6
- iOS 17+ / iPadOS 17+ / macOS 14+ / tvOS 17+ deployment targets

## Getting Started

### 1. Clone and open

```bash
cd kinema
open Kinema.xcodeproj
```

### 2. Resolve dependencies

Xcode will automatically fetch [MPVKit](https://github.com/karelrooted/MPVKit) via Swift Package Manager on first build.

### 3. Build

Select a platform scheme, then **⌘B**.

| Scheme | Platform |
|--------|----------|
| `Kinema_iOS` | iOS / iPadOS |
| `Kinema_macOS` | macOS |
| `Kinema_tvOS` | tvOS |
| `KinemaCLI` | macOS command-line tool |
| `KinemaShareExtension_iOS` / `_macOS` | Share extensions |

> Development builds in this repo often use Xcode beta via `DEVELOPER_DIR`.

### 4. macOS online media (optional)

For YouTube and streaming URLs on macOS, install yt-dlp:

```bash
brew install yt-dlp
# or run Scripts/bundle_ytdlp.sh to copy into the app bundle
```

## Architecture

```
UI (SwiftUI) → PlayerSession → MPVController → libmpv
```

| Package | Role |
|---------|------|
| `KinemaCore` | Models, state machine, preferences, events |
| `KinemaMPV` | libmpv integration and render backends |
| `KinemaPlayback` | `PlaybackEngine` protocol and session management |
| `KinemaUI` | SwiftUI player views and controls |
| `KinemaSubtitles` | Subtitle matching and Gestdown online search |
| `KinemaMedia` | URL resolution (yt-dlp on macOS) |
| `KinemaPlugins` | Swift plugin SDK (stub) |

## CLI (macOS)

Opens media in Kinema via a `kinema://` URL.

```bash
kinema-cli /path/to/video.mkv
kinema-cli --new-window "https://example.com/stream.m3u8"
```

| Option | Effect |
|--------|--------|
| `--new-window` | Ask the app to load in a separate session / window |
| `-h`, `--help` | Show usage |

## Deep Links

Currently applied by the app:

```
kinema://open?url=<encoded-url>
kinema://open?url=<url>&new_window=1
```

The parser also accepts `pip`, `full_screen`, `enqueue`, and `mpv_*` query items for forward compatibility; they are **not applied** yet (Picture-in-Picture is tracked separately).

## Keyboard Shortcuts (macOS)

Defaults (customize in **Preferences → Keyboard Shortcuts**):

| Key | Action |
|-----|--------|
| Space | Play / Pause |
| ← / J | Seek back (step) |
| → / L | Seek forward (step) |
| K | Pause |
| F | Toggle fullscreen |
| M | Mute |
| ↑ / ↓ | Volume |
| [ / ] | Speed down / up |
| , / . | Previous / next chapter |
| B | A–B loop (set A / set B / clear) |
| A / V | Cycle audio / subtitles |
| G / H | Subtitle delay −/+ 0.1s |

Seek step (5 / 10 / 15 / 30s) is set in **Preferences → Seek Step**.

## Regenerating mpv Bindings

When updating libmpv, regenerate Swift bindings from mpv documentation:

```bash
ruby Scripts/generate_mpv_bindings.rb
```

## Licensing

Kinema application code is licensed under the **MIT License**.

Bundled **libmpv** and **FFmpeg** libraries (via MPVKit) are subject to **LGPL v3** (or GPL v3 if GPL-enabled binaries are used). See [LICENSES/](LICENSES/) for full attribution and source-offer information.

## Acknowledgments

- [IINA](https://github.com/iina/iina) — architectural inspiration
- [mpv](https://mpv.io) — playback engine
- [MPVKit](https://github.com/karelrooted/MPVKit) — Apple platform libmpv bindings
