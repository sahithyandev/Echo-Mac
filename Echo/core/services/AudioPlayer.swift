import AVFoundation

public class AudioPlayer {
    private var player: AVAudioPlayer?
    public weak var delegate: AVAudioPlayerDelegate?

    public var isPlaying: Bool { player?.isPlaying ?? false }
    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }

    public init() {}

    public func play(_ song: Song) throws {
        player = try AVAudioPlayer(contentsOf: song.url)
        player?.delegate = delegate
        player?.play()
    }

    public func pause() {
        player?.pause()
    }

    public func resume() {
        player?.play()
    }

    public func seek(to time: TimeInterval) {
        player?.currentTime = time
    }
}
