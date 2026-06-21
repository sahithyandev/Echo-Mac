import AVFoundation

/// Extracts audio features from a song file using ID3 metadata tags.
/// Falls back gracefully — any tag that's missing or unparseable leaves
/// the corresponding field nil, which the similarity engine skips.
public actor FeatureExtractor {
    public init() {}

    public func extract(from url: URL) async throws -> TrackFeatures {
        var features = TrackFeatures(songURL: url)

        let asset = AVURLAsset(url: url)

        // Duration (always available for valid audio files)
        let duration = try await asset.load(.duration)
        features.durationSeconds = duration.seconds

        let metadata = try await asset.load(.metadata)

        // BPM from ID3 TBPM tag
        let bpmItems = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .id3MetadataBeatsPerMinute)
        if let item = bpmItems.first,
           let str = try? await item.load(.stringValue),
           let bpm = Double(str), bpm > 0 {
            features.tempoEstimate = bpm
        }

        // Musical key from ID3 TKEY tag (e.g. "Am", "C#", "Bbm")
        let keyItems = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .id3MetadataInitialKey)
        if let item = keyItems.first,
           let str = try? await item.load(.stringValue),
           let parsed = Self.parseKey(str) {
            features.key = parsed.pitchClass
            features.mode = parsed.isMinor ? 0 : 1
        }

        // Genre from common metadata (maps to TCON in ID3, ©gen in iTunes/AAC)
        let genreItems = AVMetadataItem.metadataItems(
            from: metadata,
            withKey: AVMetadataKey.commonKeyType,
            keySpace: .common)
        if let item = genreItems.first,
           let genre = try? await item.load(.stringValue) {
            features.genre = genre
        }

        return features
    }

    // TKEY values: note name + optional accidental + optional "m" for minor.
    // Examples: "C", "C#", "Db", "Am", "F#m", "Bbm"
    static func parseKey(_ raw: String) -> (pitchClass: Int, isMinor: Bool)? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let isMinor = s.hasSuffix("m")
        let note = isMinor ? String(s.dropLast()) : s

        let pitchClass: Int
        switch note {
        case "C":       pitchClass = 0
        case "C#", "Db": pitchClass = 1
        case "D":       pitchClass = 2
        case "D#", "Eb": pitchClass = 3
        case "E":       pitchClass = 4
        case "F":       pitchClass = 5
        case "F#", "Gb": pitchClass = 6
        case "G":       pitchClass = 7
        case "G#", "Ab": pitchClass = 8
        case "A":       pitchClass = 9
        case "A#", "Bb": pitchClass = 10
        case "B":       pitchClass = 11
        default:        return nil
        }
        return (pitchClass, isMinor)
    }
}
