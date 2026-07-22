import Foundation
import AppKit
import Combine

@MainActor
class MusicLibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?

    private var source: (any LibrarySource)?

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
        let source = LocalLibrarySource(directory: directoryURL)
        self.source = source
        Task {
            do {
                songs = try await source.listSongs()
                await loadMetadata()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMetadata() async {
        guard let source else { return }
        let (updated, artwork) = await source.loadMetadata(for: songs)
        for (url, data) in artwork {
            if let image = ArtworkCache.decode(data) {
                ArtworkCache.shared.set(image, for: url)
            }
        }
        songs = updated
    }
}
