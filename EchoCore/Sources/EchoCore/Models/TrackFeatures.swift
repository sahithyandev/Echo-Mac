import Foundation

/// Audio features extracted from a song, used as the input vector for similarity comparison.
public struct TrackFeatures: Codable, Sendable {
    public let songURL: URL
    public let extractedAt: Date

    // Music Understanding features
    public var tempoEstimate: Double?       // BPM
    public var key: Int?                    // 0–11 pitch class (C=0, C#=1, …, B=11)
    public var mode: Int?                   // 0=minor, 1=major
    public var averageLoudness: Double?     // dBFS (negative values, e.g. -14.0)
    public var rhythmStrength: Double?      // normalised 0–1
    public var instrumentActivity: Double?  // normalised 0–1

    // From AVURLAsset
    public var durationSeconds: Double?

    public init(songURL: URL) {
        self.songURL = songURL
        self.extractedAt = Date()
    }
}
