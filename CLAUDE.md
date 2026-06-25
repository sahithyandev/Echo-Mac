# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Echo is a macOS music player app built with SwiftUI, targeting macOS 26.5+, written in Swift 5. It reads MP3 files from the user's `~/Music` directory and provides full playback controls including system-level Now Playing integration.

## Building & Running

Open `Echo.xcodeproj` in Xcode and run with ⌘R, or build from the command line:

```bash
xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug build
```

Run tests:
```bash
xcodebuild -project Echo.xcodeproj -scheme Echo -configuration Debug test
```

## Architecture

The app follows MVVM. The core library lives in the `EchoCore` Swift package (`EchoCore/`); the app target (`Echo/`) owns all SwiftUI concerns.

### EchoCore package (`EchoCore/Sources/EchoCore/`)

- **`Models/Song.swift`** — `Song` struct with `id`, `url`, `title`, `artist`, `album`, `artwork`.
- **`Models/TrackFeatures.swift`** — Audio features extracted per track: `stableId` (Chromaprint fingerprint), BPM, key, energy, valence, artist/album/year/genre tags.
- **`Models/Recommendation.swift`** — Wraps a `Song` with a similarity `score`.
- **`Services/AudioPlayer.swift`** — Thin `AVAudioPlayer` wrapper: `play(_:)`, `pause()`, `resume()`, `seek(to:)`. Exposes `isPlaying`, `currentTime`, `duration`.
- **`Services/MusicLibrary.swift`** — `songs(in:)` scans a directory for `.mp3` files and returns them sorted alphabetically.
- **`Services/NowPlayingService.swift`** — Registers handlers on `MPRemoteCommandCenter` (play/pause, next/prev, seek) and updates `MPNowPlayingInfoCenter` including async artwork loading.
- **`Services/Fingerprinter.swift`** — Chromaprint-based acoustic fingerprinting; produces a stable `stableId` per track regardless of filename or metadata.
- **`Services/FeatureExtractor.swift`** — Extracts `TrackFeatures` (fingerprint + ID3 metadata) from an audio file URL.
- **`Services/FeatureStore.swift`** — On-disk cache of `TrackFeatures`, keyed by URL. Loads lazily and persists to disk.
- **`Services/SimilarityEngine.swift`** — Cosine-similarity ranking over `TrackFeatures` vectors; used to generate recommendations.

### App layer (`Echo/`)

#### `core/`

- **`PlaybackStore.swift`** — Raw SQLite3 analytics store (no third-party ORM). Tracks `events` (play/skip/complete/milestones), `listening` seconds per day, `songs` dimension table (artist/album/year/genre), and `song_paths` for fingerprint reconciliation. Exposes queries for listening totals, per-day history, likeability scores, top artists/albums/genres/years, and library counts.
- **`models/AppNavigationState.swift`** — `@MainActor ObservableObject`. Holds `currentPage: Page` for app-level navigation.
- **`models/Page.swift`** — `enum Page`: `.home`, `.nowPlaying`, `.stats`, `.settings`.

#### `ui/`

- **`Theme.swift`** — `AppColor` enum with named palette entries backed by asset catalog colors (`navy`, `accent`, `cream`, `tealDark`, `tealLight`).
- **`ArtworkCache.swift`** — In-memory `NSCache` for decoded `NSImage` artwork, keyed by song URL.
- **`viewmodels/AudioPlayerViewModel.swift`** — `@MainActor ObservableObject`. Owns `AudioPlayer`, `NowPlayingService`, `FeatureStore`, `FeatureExtractor`, and `SimilarityEngine`. Manages the play queue, shuffle mode, current index, progress polling timer, playback event tracking (milestones + completions), listening-time accrual, fingerprint reconciliation, and recommendations. Publishes `nowPlaying`, `isPlaying`, `progress`, `duration`, `timeRemaining`, `isShuffled`, `recommendations`.
- **`viewmodels/MusicLibraryViewModel.swift`** — `@MainActor ObservableObject`. Calls `MusicLibrary`, loads ID3 metadata (title/artist/album/artwork) async via `AVURLAsset`, and publishes `songs`.
- **`views/Root.swift`** — Top-level navigation container; switches between pages using `AppNavigationState`.
- **`views/Home.swift`** — Song list with `SongRow` thumbnails. Floating `PlayerControlsView` animates in from the bottom when a song is playing. Shows a `RecommendedSongsStrip` when recommendations are available.
- **`views/NowPlayingView.swift`** — Full-screen now-playing page: large artwork, title/artist, playback controls, `Scrubber`, shuffle toggle, and a `RecommendedSongsStrip`.
- **`views/PlayerControlsView.swift`** — Floating dark bar: artwork, title, prev/play/next buttons, and an animated progress capsule.
- **`views/SongRow.swift`** — Single row in the song list: artwork thumbnail, title, artist.
- **`views/SongArtworkView.swift`** — Async artwork loader using `AVURLAsset` metadata; shows a music-note icon fallback while loading or when no artwork exists.
- **`views/Scrubber.swift`** — Interactive seek bar with elapsed/remaining time labels.
- **`views/StatsView.swift`** — Listening stats page: today/week/all-time totals, a 30-day bar chart (`Sparkline`), library counts, and ranked lists for top artists, albums, genres, and years.
- **`views/Sparkline.swift`** — Reusable bar-chart view used in `StatsView`.
- **`views/RecommendedSongsStrip.swift`** — Horizontal scroll strip of recommended songs, shown on Home and NowPlaying.
- **`views/Settings.swift`** — Library directory picker and duplicate-track detector (groups tracks by Chromaprint fingerprint, shows file paths, and offers one-click move to Trash).

### Entry point

- **`EchoApp.swift`** — `@main` entry, renders `Root` inside a `WindowGroup`.

## Learning Goals

The developer is actively learning Swift, SwiftUI, and macOS native app development through this project. When asked to implement or change something:

- **Explain first, then implement.** Walk through the relevant Swift/SwiftUI concepts before or alongside writing code.
- **Prioritize conceptual clarity.** Explain *why* something works the way it does, not just *what* to write — cover things like property wrappers, the SwiftUI render cycle, value vs reference types, actors, etc. as they come up.
- **Assume familiarity with programming in general** but not with Swift or Apple's frameworks. Draw analogies to general programming concepts when useful.
- **Keep explanations tight.** A few well-chosen sentences beats a wall of text. Surface the mental model quickly.

## Daily Devlog

At the end of each day, a devlog entry is written to `devlogs/YYYY-MM-DD.md` summarizing the day's commits as a blog post intended for publication. When asked to write the devlog:

- Base it on `git log` for commits made that day.
- Group commits thematically rather than listing them one by one.
- Write in first person, conversational but technically honest — no hype.
- Keep it concise: a few short sections, no padding.
- Include a brief "What's next" note at the end.

## Conventions

- Views own their view models via `@StateObject`; child views receive them as `@ObservedObject`.
- All view model methods are called from `.onAppear` or user gestures — no side effects in body.
- `core/` services are plain classes (not actors); thread-safety is the view model's responsibility via `@MainActor`.
