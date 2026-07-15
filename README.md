# Echo

A macOS music player built with SwiftUI.

## License

MIT (see `LICENSE`). Statically links Chromaprint (LGPL-2.1) — see
`THIRD_PARTY_LICENSES.md` for compliance details.

## Requirements

- macOS 26.5+
- Xcode 26+

## Getting Started

Open `Echo.xcodeproj` in Xcode and run with ⌘R.

## Features

- Scans `~/Music` (or a custom directory) for MP3 files
- Song list with inline album artwork thumbnails and artist names
- Tap-to-play with a floating player bar that slides up from the bottom
- Full-screen Now Playing view with large artwork, seek bar, and shuffle toggle
- Play/pause, previous, next, and shuffle controls
- Interactive seek bar with elapsed/remaining time
- Album artwork displayed in the song list, floating bar, and Now Playing view
- System-level Now Playing integration (menu bar, lock screen, media keys)
- Acoustic fingerprinting via Chromaprint for stable track identity across renames/moves
- Duplicate track detection in Settings (groups by fingerprint, move to Trash in one click)
- Playback analytics stored in SQLite: play/skip/complete events and listening time per day
- Stats page: today/week/all-time listening totals, 30-day bar chart, top artists/albums/genres/years
- Song recommendations based on acoustic similarity + likeability score, shown as a horizontal strip

## Project Structure

```
Echo/                               # App target
├── core/
│   ├── PlaybackStore.swift         # SQLite analytics (events, listening, songs, paths)
│   ├── models/
│   │   ├── Song.swift              # Song data model (title, artist, album, artwork)
│   │   ├── TrackFeatures.swift     # Acoustic features + ID3 metadata per track
│   │   ├── Recommendation.swift    # Song + similarity score
│   │   ├── AppNavigationState.swift # App-level navigation state
│   │   └── Page.swift              # Page enum (home/nowPlaying/stats/settings)
│   └── services/
│       ├── AudioPlayer.swift       # AVAudioPlayer wrapper (play/pause/seek)
│       ├── MusicLibrary.swift      # Scans directory for MP3s
│       ├── NowPlayingService.swift # MPRemoteCommandCenter + MPNowPlayingInfoCenter
│       ├── Fingerprinter.swift     # Chromaprint acoustic fingerprinting
│       ├── FeatureExtractor.swift  # Extracts TrackFeatures from a URL
│       ├── FeatureStore.swift      # On-disk TrackFeatures cache
│       ├── SimilarityEngine.swift  # Cosine-similarity recommendations
│       └── RecommendationEngine.swift # Recommendation pipeline orchestration
└── ui/
    ├── Theme.swift                 # AppColor palette
    ├── ArtworkCache.swift          # NSCache for decoded artwork images
    ├── viewmodels/
    │   ├── AudioPlayerViewModel.swift   # Playback, queue, shuffle, analytics, recommendations
    │   └── MusicLibraryViewModel.swift # Song list + async ID3 metadata loading
    └── views/
        ├── Root.swift              # Top-level navigation container
        ├── Home.swift              # Song list + floating player + recommendations strip
        ├── NowPlayingView.swift    # Full-screen now playing page
        ├── PlayerControlsView.swift # Floating bottom player bar
        ├── SongRow.swift           # Song list row (artwork, title, artist)
        ├── SongArtworkView.swift   # Async artwork loader with fallback icon
        ├── Scrubber.swift          # Interactive seek bar
        ├── StatsView.swift         # Listening stats + charts
        ├── Sparkline.swift         # Reusable bar chart
        ├── RecommendedSongsStrip.swift # Horizontal recommendations scroll
        └── Settings.swift          # Library path picker + duplicate detector
```
