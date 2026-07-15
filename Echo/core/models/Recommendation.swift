import Foundation

/// A song recommended based on similarity to a seed track.
public struct Recommendation: Sendable {
    public let songURL: URL
    /// Similarity score from 0 (no match) to 1 (identical features).
    public let similarityScore: Double

    public init(songURL: URL, similarityScore: Double) {
        self.songURL = songURL
        self.similarityScore = similarityScore
    }
}
