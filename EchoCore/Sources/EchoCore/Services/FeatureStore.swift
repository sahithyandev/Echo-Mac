import Foundation

/// Persistent cache for TrackFeatures, backed by a single JSON file.
///
/// Cache invalidation: if the source file's modification date is newer than
/// `extractedAt`, the entry is treated as stale and re-extraction is triggered.
public actor FeatureStore {
    private let storeURL: URL
    private var cache: [String: TrackFeatures] = [:]
    private var loaded = false

    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    /// Read the on-disk cache into memory. Idempotent — safe to call multiple times.
    public func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: TrackFeatures].self, from: data)
        else { return }
        cache = decoded
    }

    /// Returns cached features for `url`, or nil if not cached or the source file changed.
    public func features(for url: URL) -> TrackFeatures? {
        guard let cached = cache[url.absoluteString] else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        if let modDate = attrs?[.modificationDate] as? Date, modDate > cached.extractedAt {
            return nil  // source file changed since last extraction
        }
        return cached
    }

    /// Stores features and atomically persists the full cache to disk.
    /// Atomic write: Data writes to a temp file, then renames — safe against mid-write crashes.
    public func save(_ features: TrackFeatures) throws {
        cache[features.songURL.absoluteString] = features
        let data = try JSONEncoder().encode(cache)
        try data.write(to: storeURL, options: .atomic)
    }

    /// For each URL not in cache (or stale), runs extraction and saves the result.
    /// Errors on individual songs are silently skipped so one bad file doesn't abort the batch.
    public func ensureFeatures(for urls: [URL], using extractor: FeatureExtractor) async {
        for url in urls {
            guard features(for: url) == nil else { continue }
            guard let extracted = try? await extractor.extract(from: url) else { continue }
            try? save(extracted)
        }
    }

    /// Returns all cached entries — used by the similarity engine to build the feature library.
    public func allFeatures() -> [TrackFeatures] {
        Array(cache.values)
    }
}
