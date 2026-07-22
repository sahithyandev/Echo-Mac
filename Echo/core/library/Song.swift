import Foundation

public struct Song: Identifiable, Equatable {
    public let id: UUID = UUID()
    public let url: URL
    public var title: String
    public var artist: String?
    public var album: String?
    /// The Library.id this song was scanned from. Nil only for songs constructed
    /// outside a library scan (shouldn't happen in practice).
    public var libraryId: String?

    public init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }
}
