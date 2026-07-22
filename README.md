# Kinema

**Kinema** is a modern, cross-platform video player for **iOS**, **iPadOS**, **macOS**, and **tvOS**, inspired by [IINA](https://github.com/iina/iina) and powered by **libmpv**.

> κίνημα — motion, cinema

## Features

- Broad format support via libmpv / FFmpeg (H.264, H.265, AV1, VP9, MKV, and more)
- Unified SwiftUI interface across Apple platforms
- Subtitles: auto-match, manual load, OpenSubtitles search, styling
- Playlists, chapters, A/V track selection
- Playback history with resume (SwiftData)
- Picture-in-Picture (iOS / macOS)
- Gesture controls and keyboard shortcuts
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

Select the **Kinema** scheme and your target platform, then **⌘B**.

| Scheme | Platform |
|--------|----------|
| Kinema | iOS / iPadOS / macOS / tvOS |
| KinemaCLI | macOS command-line tool |
| KinemaShareExtension | iOS / macOS share extension |

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
| `KinemaSubtitles` | Subtitle matching and OpenSubtitles API |
| `KinemaMedia` | URL resolution (yt-dlp on macOS) |
| `KinemaPlugins` | Swift plugin SDK (stub) |

## CLI (macOS)

```bash
kinema-cli /path/to/video.mkv
kinema-cli --new-window --pip "https://example.com/stream.m3u8"
kinema-cli --mpv-volume=80 video.mp4
```

## Deep Links

```
kinema://open?url=<encoded-url>
kinema://open?url=<url>&pip=1&new_window=1
```

## Keyboard Shortcuts (macOS)

| Key | Action |
|-----|--------|
| Space | Play / Pause |
| ← / → | Seek ±5s |
| J / K / L | Seek back / Pause / Seek forward |
| F | Toggle fullscreen |
| M | Mute |
| ↑ / ↓ | Volume ±5% |

Customize in **Settings → Keyboard**.

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
