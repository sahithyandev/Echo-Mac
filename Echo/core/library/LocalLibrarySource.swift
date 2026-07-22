import Foundation
import AVFoundation

/// Scans a local directory for MP3 files and enriches them with ID3 metadata.
public final class LocalLibrarySource: LibrarySource {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func listSongs() throws -> [Song] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls: [URL] = enumerator.compactMap { $0 as? URL }
        let mp3URLs = urls.filter { $0.pathExtension.lowercased() == "mp3" }
        let sorted = mp3URLs.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return sorted.map { Song(url: $0) }
    }

    public func loadMetadata(for songs: [Song]) async -> (songs: [Song], artwork: [URL: Data]) {
        var updated = songs
        var artwork: [URL: Data] = [:]

        for i in updated.indices {
            let url = updated[i].url
            let asset = AVURLAsset(url: url)
            guard let items = try? await asset.load(.commonMetadata) else { continue }

            var title: String?
            var artist: String?
            var album: String?

            for item in items {
                switch item.commonKey {
                case .commonKeyTitle:
                    title = try? await item.load(.stringValue)
                case .commonKeyArtist:
                    artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    album = try? await item.load(.stringValue)
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        artwork[url] = data
                    }
                default:
                    break
                }
            }

            if let title { updated[i].title = title }
            updated[i].artist = artist
            updated[i].album = album
        }

        return (updated, artwork)
    }
}
