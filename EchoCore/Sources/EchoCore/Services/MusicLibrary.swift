import Foundation

public class MusicLibrary {
    public init() {}

    public func songs(in directoryURL: URL) throws -> [Song] {
        try FileManager.default
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Song(url: $0) }
    }
}
