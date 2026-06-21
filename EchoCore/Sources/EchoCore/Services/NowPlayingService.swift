import MediaPlayer
import AVFoundation
import AppKit

// @unchecked Sendable: allows [weak self] capture across the nonisolated
// MPRemoteCommandCenter boundary. Thread safety is upheld because:
// - callbacks are always set/called on the main thread (via DispatchQueue.main.async)
// - update() and clear() are only ever called by @MainActor AudioPlayerViewModel
// - MPNowPlayingInfoCenter is updated from the artwork Task (background thread),
//   which avoids a deadlock with MediaPlayer's internal accessQueue.
// Do NOT add @MainActor to this class or its methods — see above.
public final class NowPlayingService: @unchecked Sendable {
    // @MainActor matches the implicit isolation the app gives to closures it assigns here
    // (the app target has SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
    @MainActor public var onTogglePlayPause: (() -> Void)?
    @MainActor public var onNext: (() -> Void)?
    @MainActor public var onPrev: (() -> Void)?
    @MainActor public var onSeek: ((TimeInterval) -> Void)?

    private var artworkCache: [URL: MPMediaItemArtwork] = [:]
    private var artworkLoadingURL: URL?

    public init() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPause?() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPause?() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTogglePlayPause?() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNext?() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPrev?() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                let positionTime = e.positionTime
                Task { @MainActor [weak self] in self?.onSeek?(positionTime) }
            }
            return .success
        }
    }

    public func update(song: Song, currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        if let cached = artworkCache[song.url] {
            var info = Self.makeInfo(title: song.title, currentTime: currentTime, duration: duration, isPlaying: isPlaying)
            info[MPMediaItemPropertyArtwork] = cached
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
            return
        }

        guard artworkLoadingURL != song.url else { return }
        artworkLoadingURL = song.url

        // Capture only Sendable values — [String: Any] is not Sendable,
        // so we rebuild the dict inside the Task.
        let title = song.title
        let url = song.url
        Task {
            var info = Self.makeInfo(title: title, currentTime: currentTime, duration: duration, isPlaying: isPlaying)
            if let image = await self.loadArtwork(from: url) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.artworkCache[url] = artwork
                info[MPMediaItemPropertyArtwork] = artwork
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }

    public func clear() {
        artworkLoadingURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private static func makeInfo(title: String, currentTime: TimeInterval, duration: TimeInterval, isPlaying: Bool) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func loadArtwork(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items {
            guard item.commonKey == .commonKeyArtwork else { continue }
            guard let data = try? await item.load(.dataValue) else { continue }
            return NSImage(data: data)
        }
        return nil
    }
}
