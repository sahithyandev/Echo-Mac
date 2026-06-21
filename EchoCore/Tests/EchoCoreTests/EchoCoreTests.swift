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
