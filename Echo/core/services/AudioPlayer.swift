import AVFoundation

class AudioPlayer {
    private var player: AVAudioPlayer?
    weak var delegate: AVAudioPlayerDelegate?

    var isPlaying: Bool { player?.isPlaying ?? false }
    var currentTime: TimeInterval { player?.currentTime ?? 0 }
    var duration: TimeInterval { player?.duration ?? 0 }

    func play(_ song: Song) throws {
        player = try AVAudioPlayer(contentsOf: song.url)
        player?.delegate = delegate
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }
}
