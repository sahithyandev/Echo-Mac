import Foundation
import AppKit
import AVFoundation
import Combine

@MainActor
class MusicLibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?

    private let library = MusicLibrary()

    func songs(inAlbum name: String) -> [Song] {
        songs.filter { ($0.album ?? "Unknown Album") == name }
    }

    func songs(byArtist name: String) -> [Song] {
        songs.filter { artistNames(for: $0).contains(name) }
    }

    func artistNames(for song: Song) -> [String] {
        guard let raw = song.artist, !raw.isEmpty else { return ["Unknown Artist"] }
        let names = PlaybackStore.splitArtists(raw)
        return names.isEmpty ? ["Unknown Artist"] : names
    }

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
                    if let data = try? await item.load(.dataValue), let image = ArtworkCache.decode(data) {
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
