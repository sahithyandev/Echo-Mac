import AVFoundation
import Accelerate

/// Extracts audio features from a song file.
/// ID3 tags provide BPM, key, and genre (present in well-tagged libraries).
/// RMS loudness is computed from the raw PCM samples and is always available.
public actor FeatureExtractor {
    public init() {}

    public func extract(from url: URL) async throws -> TrackFeatures {
        var features = TrackFeatures(songURL: url)

        let asset = AVURLAsset(url: url)

        // Duration
        let duration = try await asset.load(.duration)
        features.durationSeconds = duration.seconds

        // ID3 metadata
        let metadata = try await asset.load(.metadata)

        // BPM from TBPM tag
        let bpmItems = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .id3MetadataBeatsPerMinute)
        if let item = bpmItems.first,
           let str = try? await item.load(.stringValue),
           let bpm = Double(str), bpm > 0 {
            features.tempoEstimate = bpm
        }

        // Musical key from TKEY tag (e.g. "Am", "C#", "Bbm")
        let keyItems = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .id3MetadataInitialKey)
        if let item = keyItems.first,
           let str = try? await item.load(.stringValue),
           let parsed = Self.parseKey(str) {
            features.key = parsed.pitchClass
            features.mode = parsed.isMinor ? 0 : 1
        }

        // Genre from common metadata (TCON in ID3, ©gen in iTunes/AAC)
        let genreItems = AVMetadataItem.metadataItems(
            from: metadata,
            withKey: AVMetadataKey.commonKeyType,
            keySpace: .common)
        if let item = genreItems.first,
           let genre = try? await item.load(.stringValue) {
            features.genre = genre
        }

        // Artist — common space first (works for ID3 + iTunes), fall back to TPE1
        let artistCommon = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtist)
        if let item = artistCommon.first,
           let artist = try? await item.load(.stringValue), !artist.isEmpty {
            features.artist = artist
        } else {
            let artistID3 = AVMetadataItem.metadataItems(
                from: metadata, filteredByIdentifier: .id3MetadataLeadPerformer)
            if let item = artistID3.first,
               let artist = try? await item.load(.stringValue), !artist.isEmpty {
                features.artist = artist
            }
        }

        // Album — common space first, fall back to TALB
        let albumCommon = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierAlbumName)
        if let item = albumCommon.first,
           let album = try? await item.load(.stringValue), !album.isEmpty {
            features.album = album
        } else {
            let albumID3 = AVMetadataItem.metadataItems(
                from: metadata, filteredByIdentifier: .id3MetadataAlbumTitle)
            if let item = albumID3.first,
               let album = try? await item.load(.stringValue), !album.isEmpty {
                features.album = album
            }
        }

        // Year — try TDRC (ID3v2.4), TYER (ID3v2.3), then common creation date
        let yearSources: [AVMetadataIdentifier] = [
            .id3MetadataRecordingTime,
            .id3MetadataYear,
            .commonIdentifierCreationDate,
        ]
        for id in yearSources {
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id)
            if let item = items.first,
               let str = try? await item.load(.stringValue),
               let y = Self.parseYear(str) {
                features.year = y
                break
            }
        }

        // RMS loudness — always computable, no tags needed
        features.averageLoudness = Self.computeRMS(url: url)

        return features
    }

    // Reads decoded PCM samples in chunks and computes overall RMS loudness in dBFS.
    // Uses channel 0 only — L and R are highly correlated in typical music.
    // vDSP_rmsqv computes sqrt(sum(x²)/n) for a Float array in a single pass.
    static func computeRMS(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.processingFormat
        let chunkSize: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            return nil
        }

        var totalSumOfSquares: Double = 0
        var totalFrames: Int = 0

        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0, let channel = buffer.floatChannelData?[0] else { break }

            // vDSP_rmsqv: result = sqrt( sum(channel[i]²) / n )
            // so channel[i]² sum = result² × n
            var rms: Float = 0
            vDSP_rmsqv(channel, 1, &rms, vDSP_Length(n))
            totalSumOfSquares += Double(rms * rms) * Double(n)
            totalFrames += n
        }

        guard totalFrames > 0 else { return nil }
        let overallRMS = sqrt(totalSumOfSquares / Double(totalFrames))
        guard overallRMS > 0 else { return nil }
        return 20 * log10(overallRMS)   // dBFS, e.g. -14.0 for a loud track
    }

    // Pulls the first 4-digit year from strings like "2001", "2001-05-03", "2001-05".
    static func parseYear(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard s.count >= 4, let y = Int(s.prefix(4)), y >= 1000, y <= 9999 else { return nil }
        return y
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
        case "C":         pitchClass = 0
        case "C#", "Db": pitchClass = 1
        case "D":         pitchClass = 2
        case "D#", "Eb": pitchClass = 3
        case "E":         pitchClass = 4
        case "F":         pitchClass = 5
        case "F#", "Gb": pitchClass = 6
        case "G":         pitchClass = 7
        case "G#", "Ab": pitchClass = 8
        case "A":         pitchClass = 9
        case "A#", "Bb": pitchClass = 10
        case "B":         pitchClass = 11
        default:          return nil
        }
        return (pitchClass, isMinor)
    }
}
