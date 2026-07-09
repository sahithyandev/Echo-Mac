import AppKit
import ImageIO

final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        // Bound by decoded byte size so a big library can't balloon memory;
        // NSCache also evicts automatically under system memory pressure.
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func get(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func set(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Decode embedded artwork downsampled to at most `maxPixel` on the long side.
    /// ImageIO decodes directly at the target size — a 3000×3000 cover never
    /// materializes as a full-resolution bitmap just to draw a 44pt row thumbnail.
    static func decode(_ data: Data, maxPixel: CGFloat = 1024) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return NSImage(data: data) }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
