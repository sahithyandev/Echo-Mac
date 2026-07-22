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
        if (cached.schemaVersion ?? 1) < TrackFeatures.currentSchemaVersion {
            return nil  // new fields added; re-extract
        }
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
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(cache)
        try data.write(to: storeURL, options: .atomic)
    }

    /// For each URL not in cache (or stale), runs extraction and saves the result.
    /// Errors on individual songs are silently skipped so one bad file doesn't abort the batch.
    /// Persists every 10 extractions (not per song) so a large import doesn't rewrite
    /// the growing store file N times, while a crash mid-batch loses at most 10 songs' work.
    public func ensureFeatures(for urls: [URL], using extractor: FeatureExtractor) async {
        var pending = 0
        for url in urls {
            guard features(for: url) == nil else { continue }
            guard let extracted = try? await extractor.extract(from: url) else { continue }
            cache[extracted.songURL.absoluteString] = extracted
            pending += 1
            if pending >= 10 { try? persist(); pending = 0 }
        }
        if pending > 0 { try? persist() }
    }

    /// Returns all cached entries — used by the similarity engine to build the feature library.
    public func allFeatures() -> [TrackFeatures] {
        Array(cache.values)
    }
}
