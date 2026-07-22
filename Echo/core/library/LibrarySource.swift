import Foundation

/// A source of songs — a local directory today, potentially a Subsonic server later.
public protocol LibrarySource {
    /// Fast: return the track list. Titles may be filename-derived placeholders
    /// until `loadMetadata` enriches them.
    func listSongs() async throws -> [Song]

    /// Slow: enrich songs with real metadata. Returns the updated songs plus any
    /// embedded artwork found, keyed by song URL — the caller decides how (or
    /// whether) to cache it, keeping this layer free of UI-side concerns.
    func loadMetadata(for songs: [Song]) async -> (songs: [Song], artwork: [URL: Data])
}
