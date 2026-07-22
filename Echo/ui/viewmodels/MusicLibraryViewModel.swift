import Foundation
import AppKit
import Combine

@MainActor
class MusicLibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?
    @Published private(set) var libraries: [Library]

    private static let defaultsKey = "libraries"
    // ponytail: migrate the old single-directory AppStorage key rather than losing the user's setting
    private static let legacyDirectoryKey = "libraryDirectory"

    private var sources: [String: any LibrarySource] = [:]
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        libraries = Self.loadLibraries(from: userDefaults)
    }

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

    // MARK: - Library management

    func addLibraries(_ urls: [URL]) {
        let existingIds = Set(libraries.map(\.id))
        let new = urls.filter { !existingIds.contains($0.path) }.map { Library(path: $0.path) }
        guard !new.isEmpty else { return }
        libraries += new
        persist()
        reload()
    }

    func removeLibrary(_ id: String) {
        guard libraries.contains(where: { $0.id == id }) else { return }
        libraries.removeAll { $0.id == id }
        sources[id] = nil
        persist()
        reload()
    }

    /// Renames a library in place. No rescan needed — the name is display-only,
    /// membership is keyed by path/id.
    func renameLibrary(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = libraries.firstIndex(where: { $0.id == id }) else { return }
        libraries[index].name = trimmed
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(libraries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadLibraries(from defaults: UserDefaults) -> [Library] {
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Library].self, from: data) {
            return decoded
        }
        // Migrate the pre-multi-library single path, if present; else seed ~/Music.
        let legacyPath = defaults.string(forKey: legacyDirectoryKey)
        let path = legacyPath ?? "/Users/\(NSUserName())/Music"
        return [Library(path: path)]
    }

    // MARK: - Scanning

    /// Rescans every configured library and merges the results into `songs`.
    func reload() {
        let libraries = self.libraries
        // Attributes any listening history recorded before multi-library support
        // existed (or before a given library was added) to the library it belongs to.
        PlaybackStore.backfillLibraryIds(libraries: libraries)
        Task {
            var allSongs: [Song] = []
            var newSources: [String: any LibrarySource] = [:]
            for library in libraries {
                let source = LocalLibrarySource(directory: library.url)
                newSources[library.id] = source
                do {
                    let scanned = try await source.listSongs()
                    allSongs += scanned.map { song in
                        var s = song
                        s.libraryId = library.id
                        return s
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            sources = newSources
            songs = Self.dedupByURL(allSongs)
            await loadMetadata()
        }
    }

    /// Songs from multiple libraries can point at the same file (e.g. overlapping folders);
    /// keep the first occurrence so playback/analytics see one entry per URL.
    static func dedupByURL(_ songs: [Song]) -> [Song] {
        var seen = Set<URL>()
        return songs.filter { seen.insert($0.url).inserted }
            .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    private func loadMetadata() async {
        for (libraryId, source) in sources {
            let subset = songs.filter { $0.libraryId == libraryId }
            guard !subset.isEmpty else { continue }
            let (updated, artwork) = await source.loadMetadata(for: subset)
            for (url, data) in artwork {
                if let image = ArtworkCache.decode(data) {
                    ArtworkCache.shared.set(image, for: url)
                }
            }
            let byURL = Dictionary(uniqueKeysWithValues: updated.map { ($0.url, $0) })
            songs = songs.map { byURL[$0.url] ?? $0 }
        }
    }
}
