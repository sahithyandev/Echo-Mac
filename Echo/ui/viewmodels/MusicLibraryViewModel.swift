import Foundation
import AppKit
import AVFoundation
import Combine
import EchoCore

@MainActor
class MusicLibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?

    private let library = MusicLibrary()

    func load(from directoryURL: URL) {
        do {
            songs = try library.songs(in: directoryURL)
            Task { await loadMetadata() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMetadata() async {
        // ponytail: mutate a local copy so songs is published once, not once per song
        var updated = songs
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
                    if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
                        ArtworkCache.shared.set(image, for: url)
                    }
                default:
                    break
                }
            }

            if let title { updated[i].title = title }
            updated[i].artist = artist
            updated[i].album = album
        }
        songs = updated
    }
}
