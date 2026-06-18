import Foundation

struct Song: Identifiable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String?
    var album: String?

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }
}
