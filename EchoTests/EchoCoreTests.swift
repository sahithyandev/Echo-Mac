import Foundation
import Testing
@testable import Echo

@Suite("EchoCore")
struct EchoCoreTests {
    @Test("RecommendationEngine returns empty array before analysis")
    func recommendationsBeforeAnalysis() async {
        let url = URL(fileURLWithPath: "/tmp/fake.mp3")
        let results = await RecommendationEngine.shared.recommendations(for: url)
        #expect(results.isEmpty)
    }
}

@Suite("MusicLibrary")
struct MusicLibraryTests {
    @Test("songs(in:) recurses into subdirectories")
    func recursesIntoSubdirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("musiclibrary-test-\(UUID())")
        let nested = root.appendingPathComponent("Artist/Album")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: root.appendingPathComponent("top.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("nested.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("ignore.txt").path, contents: Data())

        let songs = try MusicLibrary().songs(in: root)

        #expect(songs.map(\.title).sorted() == ["nested", "top"])
    }
}

@Suite("FeatureExtractor")
struct FeatureExtractorTests {
    @Test("parseKey handles major keys")
    func majorKeys() {
        #expect(FeatureExtractor.parseKey("C")?.pitchClass == 0)
        #expect(FeatureExtractor.parseKey("C")?.isMinor == false)
        #expect(FeatureExtractor.parseKey("C#")?.pitchClass == 1)
        #expect(FeatureExtractor.parseKey("Db")?.pitchClass == 1)
        #expect(FeatureExtractor.parseKey("F#")?.pitchClass == 6)
        #expect(FeatureExtractor.parseKey("Bb")?.pitchClass == 10)
        #expect(FeatureExtractor.parseKey("B")?.pitchClass == 11)
    }

    @Test("parseKey handles minor keys")
    func minorKeys() {
        #expect(FeatureExtractor.parseKey("Am")?.pitchClass == 9)
        #expect(FeatureExtractor.parseKey("Am")?.isMinor == true)
        #expect(FeatureExtractor.parseKey("F#m")?.pitchClass == 6)
        #expect(FeatureExtractor.parseKey("Bbm")?.pitchClass == 10)
        #expect(FeatureExtractor.parseKey("C#m")?.pitchClass == 1)
    }

    @Test("parseKey returns nil for unknown values")
    func unknownKey() {
        #expect(FeatureExtractor.parseKey("") == nil)
        #expect(FeatureExtractor.parseKey("X") == nil)
        #expect(FeatureExtractor.parseKey("o") == nil)
    }

    @Test("parseYear handles plain year, ISO date, and junk")
    func parseYear() {
        #expect(FeatureExtractor.parseYear("2001")       == 2001)
        #expect(FeatureExtractor.parseYear("2001-05-03") == 2001)
        #expect(FeatureExtractor.parseYear("2001-05")    == 2001)
        #expect(FeatureExtractor.parseYear("junk")       == nil)
        #expect(FeatureExtractor.parseYear("")            == nil)
        #expect(FeatureExtractor.parseYear("999")         == nil)   // too short
    }

    @Test("extract throws for non-existent file")
    func extractMissingFile() async {
        let extractor = FeatureExtractor()
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).mp3")
        await #expect(throws: (any Error).self) {
            try await extractor.extract(from: url)
        }
    }

    @Test("computeRMS returns nil for non-existent file")
    func rmsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).mp3")
        #expect(FeatureExtractor.computeRMS(url: url) == nil)
    }
}

@Suite("SimilarityEngine")
struct SimilarityEngineTests {
    private let engine = SimilarityEngine()

    private func make(_ path: String, bpm: Double? = nil, key: Int? = nil, mode: Int? = nil,
                      loudness: Double? = nil, duration: Double? = nil,
                      artist: String? = nil, album: String? = nil,
                      year: Int? = nil, genre: String? = nil) -> TrackFeatures {
        var f = TrackFeatures(songURL: URL(fileURLWithPath: path))
        f.tempoEstimate = bpm
        f.key = key
        f.mode = mode
        f.averageLoudness = loudness
        f.durationSeconds = duration
        f.artist = artist
        f.album = album
        f.year = year
        f.genre = genre
        return f
    }

    @Test("identical features produce score of 1")
    func identicalFeatures() {
        let seed = make("/a.mp3", bpm: 128, key: 0, mode: 1, loudness: -14, duration: 200)
        let copy = make("/b.mp3", bpm: 128, key: 0, mode: 1, loudness: -14, duration: 200)
        let results = engine.recommendations(for: seed, from: [seed, copy])
        #expect(results.first?.similarityScore == 1.0)
    }

    @Test("closer BPM ranks higher")
    func closerBPMRanksHigher() {
        let seed  = make("/seed.mp3",  bpm: 128)
        let close = make("/close.mp3", bpm: 130)
        let far   = make("/far.mp3",   bpm: 90)
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        let urls = results.map(\.songURL.lastPathComponent)
        #expect(urls.first == "close.mp3")
    }

    @Test("seed excluded from results")
    func seedExcluded() {
        let seed = make("/seed.mp3", bpm: 128)
        let other = make("/other.mp3", bpm: 128)
        let results = engine.recommendations(for: seed, from: [seed, other])
        #expect(!results.map(\.songURL).contains(seed.songURL))
    }

    @Test("nil features are skipped — score still computed from available features")
    func nilFeaturesSkipped() {
        let seed      = make("/seed.mp3",  bpm: 128, loudness: -14)
        let withKey   = make("/match.mp3", bpm: 128, key: 5, loudness: -14)  // same BPM + loudness
        let noFeature = make("/empty.mp3")                                    // no features
        let results = engine.recommendations(for: seed, from: [seed, withKey, noFeature])
        #expect(results.first?.songURL.lastPathComponent == "match.mp3")
    }

    @Test("same key and mode ranks above different mode")
    func keyModeRanking() {
        let seed     = make("/seed.mp3",   key: 0, mode: 1)
        let sameMode = make("/same.mp3",   key: 0, mode: 1)
        let diffMode = make("/diff.mp3",   key: 0, mode: 0)
        let results = engine.recommendations(for: seed, from: [seed, sameMode, diffMode])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("circular key distance: B and C closer than B and F#")
    func circularKeyDistance() {
        // B = 11, C = 0 → dist = min(11, 1) = 1
        // B = 11, F# = 6 → dist = min(5, 7) = 5
        let seed  = make("/seed.mp3", key: 11)
        let close = make("/c.mp3",    key: 0)   // C — 1 semitone away via octave
        let far   = make("/fs.mp3",   key: 6)   // F# — 5 semitones away
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        #expect(results.first?.songURL.lastPathComponent == "c.mp3")
    }

    @Test("same artist ranks above different artist")
    func artistRanking() {
        let seed      = make("/seed.mp3",  artist: "Radiohead")
        let sameArtist = make("/same.mp3", artist: "Radiohead")
        let diffArtist = make("/diff.mp3", artist: "Coldplay")
        let results = engine.recommendations(for: seed, from: [seed, sameArtist, diffArtist])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("closer year ranks higher")
    func yearRanking() {
        let seed  = make("/seed.mp3",  year: 2000)
        let close = make("/close.mp3", year: 2001)
        let far   = make("/far.mp3",   year: 1985)
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        #expect(results.first?.songURL.lastPathComponent == "close.mp3")
    }

    @Test("same genre ranks above different genre")
    func genreRanking() {
        let seed      = make("/seed.mp3",  genre: "Jazz")
        let sameGenre = make("/same.mp3",  genre: "Jazz")
        let diffGenre = make("/diff.mp3",  genre: "Metal")
        let results = engine.recommendations(for: seed, from: [seed, sameGenre, diffGenre])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("count is respected")
    func countRespected() {
        let seed = make("/seed.mp3", bpm: 120)
        let library = (1...20).map { make("/s\($0).mp3", bpm: Double(100 + $0)) }
        let results = engine.recommendations(for: seed, from: [seed] + library, count: 5)
        #expect(results.count == 5)
    }
}

@Suite("FeatureStore")
struct FeatureStoreTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("echocore-test-\(UUID()).json")
    }

    @Test("save and reload persists features")
    func saveAndReload() async throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let songURL = URL(fileURLWithPath: "/tmp/song.mp3")
        var features = TrackFeatures(songURL: songURL)
        features.tempoEstimate = 128.0
        features.averageLoudness = -14.5

        let store = FeatureStore(storeURL: storeURL)
        await store.load()
        try await store.save(features)

        // Fresh store, same path — simulates app relaunch
        let reloaded = FeatureStore(storeURL: storeURL)
        await reloaded.load()
        let result = await reloaded.features(for: songURL)

        #expect(result?.tempoEstimate == 128.0)
        #expect(result?.averageLoudness == -14.5)
    }

    @Test("features returns nil for unknown URL")
    func unknownURL() async {
        let store = FeatureStore(storeURL: tempStoreURL())
        await store.load()
        let result = await store.features(for: URL(fileURLWithPath: "/tmp/unknown.mp3"))
        #expect(result == nil)
    }

    @Test("allFeatures returns saved entries")
    func allFeaturesCount() async throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let store = FeatureStore(storeURL: storeURL)
        await store.load()

        for i in 0..<3 {
            var f = TrackFeatures(songURL: URL(fileURLWithPath: "/tmp/song\(i).mp3"))
            f.tempoEstimate = Double(120 + i * 10)
            try await store.save(f)
        }

        let all = await store.allFeatures()
        #expect(all.count == 3)
    }
}
