import AppKit

final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, NSImage>()
    func get(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func set(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}
