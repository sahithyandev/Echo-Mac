import AVFoundation

class AudioPlayer {
    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(_ song: Song) throws {
        player = try AVAudioPlayer(contentsOf: song.url)
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }
}
