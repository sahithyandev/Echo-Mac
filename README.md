# Echo

A macOS music player built with SwiftUI.

## Requirements

- macOS 26.5+
- Xcode 26+

## Getting Started

Open `Echo.xcodeproj` in Xcode and run with ⌘R.

## Project Structure

```
Echo/
├── core/
│   ├── models/
│   │   └── Song.swift          # Song data model
│   └── services/
│       ├── AudioPlayer.swift   # AVAudioPlayer wrapper (play/pause)
│       └── MusicLibrary.swift  # Scans Music directory for songs
└── ui/
    ├── viewmodels/
    │   ├── AudioPlayerViewModel.swift    # Publishes player state to views
    │   └── MusicLibraryViewModel.swift  # Publishes song list to views
    └── views/
        ├── Home.swift              # Main screen
        └── PlayerControlsView.swift
```

`core/` is pure Swift with no SwiftUI dependency. `ui/` consumes core services and exposes `@Published` state for SwiftUI views.
