import Foundation

struct Song: Identifiable {
    let id = UUID()
    let url: URL

    var title: String { url.deletingPathExtension().lastPathComponent }
}
