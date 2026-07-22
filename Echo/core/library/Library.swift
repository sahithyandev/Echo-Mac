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
    /// Security-scoped bookmark for `path`, so sandboxed access survives relaunch
    /// without re-prompting. Absent for the seeded default `~/Music` library, which
    /// is granted via the app's read-only Music-folder entitlement instead of a picker.
    public var bookmarkData: Data?

    public var id: String { path }

    public init(path: String, name: String? = nil, bookmarkData: Data? = nil) {
        self.path = path
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        self.name = trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed
        self.bookmarkData = bookmarkData
    }

    public var url: URL { URL(fileURLWithPath: path) }
}
