import Foundation
import Testing
@testable import EchoCore

@Suite("EchoCore")
struct EchoCoreTests {
    @Test("RecommendationEngine returns empty array before analysis")
    func recommendationsBeforeAnalysis() async {
        let url = URL(fileURLWithPath: "/tmp/fake.mp3")
        let results = await RecommendationEngine.shared.recommendations(for: url)
        #expect(results.isEmpty)
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

@Suite("FeatureStore")
struct FeatureStoreTests {
    private func tempStoreURL() -> URL {
        URL(fileURLWithPath: "/tmp/echocore-test-\(UUID()).json")
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
