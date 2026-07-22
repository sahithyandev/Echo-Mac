import Foundation

public struct SimilarityEngine {

    // Tunable weights — must sum to 1.0
    public struct Weights: Sendable {
        public var tempo: Double              = 0.20
        public var key: Double                = 0.15   // covers both pitch class and mode
        public var artist: Double             = 0.15
        public var genre: Double              = 0.10
        public var loudness: Double           = 0.10
        public var rhythm: Double             = 0.10
        public var album: Double              = 0.05
        public var year: Double               = 0.05
        public var instrumentActivity: Double = 0.05
        public var duration: Double           = 0.05

        public init() {}
    }

    public var weights: Weights

    public init(weights: Weights = Weights()) {
        self.weights = weights
    }

    public func recommendations(
        for seed: TrackFeatures,
        from library: [TrackFeatures],
        count: Int = 10
    ) -> [Recommendation] {
        let candidates = library.filter { $0.songURL != seed.songURL }
        guard !candidates.isEmpty else { return [] }

        let all = library
        let tempoRange  = featureRange(all.compactMap(\.tempoEstimate))
        let loudRange   = featureRange(all.compactMap(\.averageLoudness))
        let durRange    = featureRange(all.compactMap(\.durationSeconds))
        let yearRange   = featureRange(all.compactMap(\.year).map(Double.init))

        return candidates
            .map { candidate in
                Recommendation(
                    songURL: candidate.songURL,
                    similarityScore: similarity(seed, candidate,
                                                tempoRange: tempoRange,
                                                loudnessRange: loudRange,
                                                durationRange: durRange,
                                                yearRange: yearRange)
                )
            }
            .sorted { $0.similarityScore > $1.similarityScore }
            .prefix(count)
            .map { $0 }
    }

    // MARK: - Private

    private func similarity(
        _ a: TrackFeatures,
        _ b: TrackFeatures,
        tempoRange: ClosedRange<Double>?,
        loudnessRange: ClosedRange<Double>?,
        durationRange: ClosedRange<Double>?,
        yearRange: ClosedRange<Double>?
    ) -> Double {
        var weightedSum = 0.0
        var activeWeight = 0.0

        func contribute(_ w: Double, _ score: Double?) {
            guard let score else { return }
            weightedSum += w * score
            activeWeight += w
        }

        // Tempo: linear distance normalized by library range
        contribute(weights.tempo, linearSim(a.tempoEstimate, b.tempoEstimate, range: tempoRange))

        // Key + mode: circular pitch-class distance (0–6 semitones) blended with mode match
        contribute(weights.key, keySim(a, b))

        // Artist: exact string match (case-insensitive)
        contribute(weights.artist, exactMatchSim(a.artist, b.artist))

        // Genre: exact string match
        contribute(weights.genre, exactMatchSim(a.genre, b.genre))

        // Loudness
        contribute(weights.loudness, linearSim(a.averageLoudness, b.averageLoudness, range: loudnessRange))

        // Rhythm
        contribute(weights.rhythm, linearSim(a.rhythmStrength, b.rhythmStrength, range: 0.0...1.0))

        // Album: exact string match
        contribute(weights.album, exactMatchSim(a.album, b.album))

        // Year: linear distance normalized by library range
        contribute(weights.year, linearSim(a.year.map(Double.init), b.year.map(Double.init), range: yearRange))

        // Instrument activity
        contribute(weights.instrumentActivity, linearSim(a.instrumentActivity, b.instrumentActivity, range: 0.0...1.0))

        // Duration
        contribute(weights.duration, linearSim(a.durationSeconds, b.durationSeconds, range: durationRange))

        guard activeWeight > 0 else { return 0 }
        return weightedSum / activeWeight
    }

    /// 1.0 if both strings are equal (case-insensitive), 0.0 if both known but differ, nil if either is nil.
    private func exactMatchSim(_ a: String?, _ b: String?) -> Double? {
        guard let a, let b else { return nil }
        return a.localizedCaseInsensitiveCompare(b) == .orderedSame ? 1.0 : 0.0
    }

    /// 1 − normalised absolute difference.  Returns nil if either value is nil.
    private func linearSim(_ x: Double?, _ y: Double?, range: ClosedRange<Double>?) -> Double? {
        guard let x, let y, let range else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 1.0 }   // all values identical → perfect match
        return max(0, 1.0 - abs(x - y) / span)
    }

    /// Circular semitone distance (max = 6) blended 2:1 with mode agreement.
    private func keySim(_ a: TrackFeatures, _ b: TrackFeatures) -> Double? {
        guard let ak = a.key, let bk = b.key else { return nil }
        let dist = min(abs(ak - bk), 12 - abs(ak - bk))     // 0–6
        let pitchSim = 1.0 - Double(dist) / 6.0

        // Mode contributes only when both are known; weight it 1/3 of the key contribution
        let modeSim: Double? = (a.mode != nil && b.mode != nil) ? (a.mode == b.mode ? 1.0 : 0.0) : nil

        if let modeSim {
            return pitchSim * (2.0 / 3.0) + modeSim * (1.0 / 3.0)
        }
        return pitchSim
    }

    /// Min/max range over a sequence; nil when fewer than 2 distinct values.
    private func featureRange(_ values: [Double]) -> ClosedRange<Double>? {
        guard let lo = values.min(), let hi = values.max(), lo <= hi else { return nil }
        return lo...hi
    }
}
