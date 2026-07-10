# Changelog

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

