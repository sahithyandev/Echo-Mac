import AVFoundation
import CChromaprint
import CryptoKit
import Foundation

/// Computes a Chromaprint acoustic fingerprint from a local audio file.
///
/// The fingerprint is derived from the audio waveform (first ~120 s), so it
/// survives renames, retags, and format re-encodes.  The ``stableId`` is a
/// 32-character hex prefix of SHA-256(raw fingerprint bytes) — short, URL-safe,
/// and stable across all releases of the same recording.
///
/// ``isSameRecording`` compares two fingerprints via bit-error rate (BER)
/// without any network call — useful for offline duplicate detection.
public enum Fingerprinter {

    public struct Result {
        /// 32-char hex string derived from SHA-256 of the raw fingerprint.
        /// Use this as the stable analytics/cache key.
        public let stableId: String
        /// Chromaprint base64-encoded compressed fingerprint.
        /// Store it when you want to compare recordings via ``isSameRecording``.
        public let fingerprint: String
    }

    // ponytail: 120 s matches AcoustID convention; enough for a stable fingerprint
    //           without scanning a 60-minute live recording.
    private static let maxSeconds: Double = 120

    // MARK: - Fingerprint

    /// Returns nil on any decode / Chromaprint failure (non-fatal, caller keeps going).
    public static func fingerprint(url: URL) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let nativeRate  = file.processingFormat.sampleRate
        let nativeChans = file.processingFormat.channelCount

        // Chromaprint expects interleaved Int16 mono.
        // We'll mix down to mono and convert Float32 → Int16 per chunk.
        guard let ctx = chromaprint_new(Int32(CHROMAPRINT_ALGORITHM_DEFAULT.rawValue)) else { return nil }
        defer { chromaprint_free(ctx) }

        guard chromaprint_start(ctx, Int32(nativeRate), 1) == 1 else { return nil }

        let chunkSize: AVAudioFrameCount = 65536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: chunkSize) else { return nil }

        let maxFrames = AVAudioFramePosition(maxSeconds * nativeRate)
        var fed: AVAudioFramePosition = 0

        while file.framePosition < file.length, fed < maxFrames {
            do { try file.read(into: buffer) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0, let channels = buffer.floatChannelData else { break }

            // Mix down to mono then convert Float32 → Int16
            var mono = [Int16](repeating: 0, count: n)
            let scale = Float(Int16.max)
            for i in 0 ..< n {
                var sum: Float = 0
                for c in 0 ..< Int(nativeChans) { sum += channels[c][i] }
                let avg = sum / Float(nativeChans)
                // clamp to [-1, 1] before scaling to avoid overflow
                mono[i] = Int16(max(-1.0, min(1.0, avg)) * scale)
            }

            let ok = mono.withUnsafeBytes { ptr in
                chromaprint_feed(ctx,
                                 ptr.baseAddress!.assumingMemoryBound(to: Int16.self),
                                 Int32(n))
            }
            guard ok == 1 else { return nil }
            fed += AVAudioFramePosition(n)
        }

        guard chromaprint_finish(ctx) == 1 else { return nil }

        // Raw fingerprint → stable ID
        var rawPtr: UnsafeMutablePointer<UInt32>?
        var rawSize: Int32 = 0
        guard chromaprint_get_raw_fingerprint(ctx, &rawPtr, &rawSize) == 1,
              let rawPtr, rawSize > 0 else { return nil }
        defer { chromaprint_dealloc(rawPtr) }

        let rawBytes = UnsafeRawBufferPointer(start: rawPtr, count: Int(rawSize) * MemoryLayout<UInt32>.size)
        let digest   = SHA256.hash(data: rawBytes)
        let stableId = digest.compactMap { String(format: "%02x", $0) }.joined().prefix(32).description

        // Compressed base64 fingerprint for BER comparison
        var fpPtr: UnsafeMutablePointer<CChar>?
        guard chromaprint_get_fingerprint(ctx, &fpPtr) == 1, let fpPtr else { return nil }
        defer { chromaprint_dealloc(fpPtr) }
        let fingerprint = String(cString: fpPtr)

        return Result(stableId: stableId, fingerprint: fingerprint)
    }

    // MARK: - Duplicate detection

    /// Returns true if two fingerprints represent the same underlying recording.
    /// Uses bit-error rate (BER) on the decoded integer arrays.
    /// BER < 0.10 ≈ same recording (includes slight crops / re-encodes).
    /// ponytail: O(min(|a|,|b|)) per call; acceptable for on-demand dedup, not bulk scans.
    public static func isSameRecording(
        _ a: String,
        _ b: String,
        threshold: Double = 0.10
    ) -> Bool {
        guard let da = decode(a), let db = decode(b), !da.isEmpty, !db.isEmpty else { return false }
        let len = min(da.count, db.count)
        var bits = 0
        for i in 0 ..< len { bits += (da[i] ^ db[i]).nonzeroBitCount }
        let ber = Double(bits) / Double(len * 32)
        return ber < threshold
    }

    /// Similarity score in [0, 1]: 1 = identical waveform, 0 = completely different.
    public static func similarity(_ a: String, _ b: String) -> Double {
        guard let da = decode(a), let db = decode(b), !da.isEmpty, !db.isEmpty else { return 0 }
        let len = min(da.count, db.count)
        var bits = 0
        for i in 0 ..< len { bits += (da[i] ^ db[i]).nonzeroBitCount }
        let ber = Double(bits) / Double(len * 32)
        return max(0, 1 - ber)
    }

    // MARK: - Private

    private static func decode(_ fp: String) -> [UInt32]? {
        var ptr: UnsafeMutablePointer<UInt32>?
        var size: Int32 = 0
        var encoded: Int32 = 0
        let ok = fp.withCString { cstr in
            // base64: 1 — chromaprint_get_fingerprint() returns a base64-encoded string,
            // not raw bytes. With 0 here, decode always fails and isSameRecording/similarity
            // silently return false/0 for every real fingerprint pair.
            chromaprint_decode_fingerprint(cstr, Int32(fp.utf8.count), &ptr, &size, &encoded, 1)
        }
        guard ok == 1, let ptr, size > 0 else { return nil }
        defer { chromaprint_dealloc(ptr) }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(size)))
    }
}
