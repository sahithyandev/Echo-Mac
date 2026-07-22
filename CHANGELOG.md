# Changelog

## 0.3.0

**Features**
- Support for multiple local music libraries
  By default, `~/Music` is added. Users can add/remove other local directories as libraries.

**Fixes**
- Chromaprint duplicate detection: fingerprints are now decoded correctly (previously failed silently on every real fingerprint pair)

**Internal**
- Introduced `LibrarySource` protocol, reorganized `core/` by domain
- Expanded test coverage; CI now reports code coverage
- Added a Makefile for common dev tasks

## 0.2.0

**Features**
- Albums and Artists pages
- Library scan now searches subdirectories recursively for music files, not just the top-level folder
- Rescan Library button in Settings to manually refresh the library

**Fixes**
- Progress scrubber animation glitch during playback

**Internal**
- Merged EchoCore package into Echo for easier maintenance 

## 0.0.1

Initial release. Echo is a native macOS music player that reads MP3s from `~/Music`, with no import step and no separate library database to manage.

**Features**
- Full playback controls: play/pause, next/previous, seek
- System-level Now Playing integration (Control Center, media keys, lock screen) via `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`, including artwork
- Shuffle mode that preserves the original queue order, so un-shuffling restores it exactly
- Automatic library scan of `~/Music` for `.mp3` files, sorted alphabetically
- ID3 metadata (title, artist, album, artwork) loaded asynchronously per track
- Duplicate detection using Chromaprint acoustic fingerprinting: finds the same recording across differently named or re-encoded files, shows file paths, and moves duplicates to Trash in one click
- Per-track audio features (BPM, key, energy, valence) extracted and cached on disk
- Recommendation engine that ranks your library against a seed track using cosine similarity, shown as a strip on Home and Now Playing, seeded from your last-played song on launch
- Local listening stats (SQLite): today/week/all-time totals, a 30-day activity chart, and ranked lists of top artists, albums, genres, and years
- Likeability score per song, derived from play, skip, and completion history
- Configurable library directory in Settings

