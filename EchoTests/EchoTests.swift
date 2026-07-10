import Testing
@testable import Echo

@Suite("Page")
struct PageTests {
    @Test("all pages are distinct")
    func distinctCases() {
        let pages: [Page] = [.home, .nowPlaying, .stats, .settings]
        #expect(Set(pages).count == pages.count)
    }
}
