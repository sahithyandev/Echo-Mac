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
