import Foundation
import AVFoundation
import Combine

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
        for i in songs.indices {
            let url = songs[i].url
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
                default:
                    break
                }
            }

            if let title { songs[i].title = title }
            songs[i].artist = artist
            songs[i].album = album
        }
    }
}
