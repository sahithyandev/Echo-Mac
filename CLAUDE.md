# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Echo is a macOS SwiftUI app targeting macOS 26.5+, written in Swift 5. It currently reads and lists files from the user's Music directory.

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

The app follows an MVVM pattern:

- **`EchoApp.swift`** — `@main` entry point, renders `Home` inside a `WindowGroup`.
- **`pages/`** — SwiftUI views for each screen. Currently only `Home.swift`.
- **`core/`** — `@MainActor` `ObservableObject` view models. Currently only `FileListViewModel.swift`, which uses `FileManager` to load file URLs from a directory.

Views own their view models via `@StateObject` and call load methods in `.onAppear`.
