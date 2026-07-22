import Foundation

/// A user-configured local music folder. `~/Music` is seeded by default;
/// more can be added from Settings, and any of them (including the default) can be removed.
///
/// `id` is the folder path itself rather than a generated token: it's already unique
/// (libraries are deduped by path) and stable across remove/re-add, so playback history
/// tagged under it in PlaybackStore doesn't get orphaned if the same folder is re-added later.
public struct Library: Identifiable, Codable, Equatable {
    public var path: String
    public var name: String

    public var id: String { path }

    public init(path: String, name: String? = nil) {
        self.path = path
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        self.name = trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed
    }

    public var url: URL { URL(fileURLWithPath: path) }
}
