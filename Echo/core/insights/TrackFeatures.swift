import Foundation

/// Audio features extracted from a song, used as the input vector for similarity comparison.
public struct TrackFeatures: Codable, Sendable, Identifiable {
    // Bump when new fields are added so FeatureStore knows to re-extract stale entries.
    public static let currentSchemaVersion = 3

    public var id: URL { songURL }
    public let songURL: URL
    public let extractedAt: Date
    public var schemaVersion: Int? = Self.currentSchemaVersion  // nil = pre-v2 entry

    // From ID3 tags (TBPM, TKEY, TCON, TPE1, TALB, TDRC) — populated by FeatureExtractor
    public var tempoEstimate: Double?       // BPM
    public var key: Int?                    // 0–11 pitch class (C=0, C#=1, …, B=11)
    public var mode: Int?                   // 0=minor, 1=major
    public var genre: String?               // e.g. "Electronic", "Jazz"
    public var artist: String?
    public var album: String?
    public var year: Int?

    // Placeholders for future Music Understanding Framework features
    public var averageLoudness: Double?     // dBFS
    public var rhythmStrength: Double?      // normalised 0–1
    public var instrumentActivity: Double?  // normalised 0–1

    // From AVURLAsset
    public var durationSeconds: Double?

    // Chromaprint acoustic fingerprint — computed from the audio waveform.
    // stableId: 32-char hex prefix of SHA-256(raw fingerprint), the analytics key.
    // fingerprint: compressed base64 string, used for offline duplicate detection.
    public var stableId: String?
    public var fingerprint: String?

    public init(songURL: URL) {
        self.songURL = songURL
        self.extractedAt = Date()
    }
}
