import Foundation

public class MusicLibrary {
    public init() {}

    public func songs(in directoryURL: URL) throws -> [Song] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
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
}
