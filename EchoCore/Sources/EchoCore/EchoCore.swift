import Foundation

/// Public entry point for the recommendation engine.
/// Owns the FeatureStore and FeatureExtractor; coordinates analysis and lookup.
public actor RecommendationEngine {
    public static let shared = RecommendationEngine()

    private let store: FeatureStore
    private let extractor = FeatureExtractor()

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EchoCore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = FeatureStore(storeURL: dir.appendingPathComponent("features.json"))
    }

    /// Loads the on-disk cache, then extracts features for any uncached or stale songs.
    /// Safe to call on every launch — cache hits are skipped instantly.
    public func analyze(library urls: [URL]) async throws {
        await store.load()
        await store.ensureFeatures(for: urls, using: extractor)
    }

    /// Returns the URLs of the `count` most similar songs to `url` (Step 4 — not yet implemented).
    public func recommendations(for url: URL, count: Int = 10) async -> [URL] {
        return []
    }

    /// Returns all cached feature entries — used for debug inspection.
    public func allCachedFeatures() async -> [TrackFeatures] {
        await store.allFeatures()
    }
}
