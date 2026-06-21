import Foundation

/// The public entry point for the recommendation engine.
/// Usage: call `analyze(library:)` after loading the music library,
/// then call `recommendations(for:)` whenever the user plays a song.
public actor RecommendationEngine {
    public static let shared = RecommendationEngine()

    // These will be filled in during Steps 2–4.
    private init() {}

    /// Pre-analyze a library of song URLs, caching features to disk.
    /// Safe to call repeatedly — already-cached songs are skipped.
    public func analyze(library urls: [URL]) async throws {
        // Step 3: FeatureStore + FeatureExtractor wired here.
    }

    /// Return the top `count` songs most similar to the given song URL.
    /// Returns an empty array if features haven't been extracted yet.
    public func recommendations(for url: URL, count: Int = 10) async -> [URL] {
        // Step 4: SimilarityEngine wired here.
        return []
    }
}
