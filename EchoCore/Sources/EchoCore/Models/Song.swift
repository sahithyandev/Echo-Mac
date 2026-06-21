import Foundation

public struct Song: Identifiable {
    public let id: UUID = UUID()
    public let url: URL
    public var title: String
    public var artist: String?
    public var album: String?

    public init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }
}
