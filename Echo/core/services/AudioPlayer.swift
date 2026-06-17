import AVFoundation

class AudioPlayer {
    private var player: AVAudioPlayer?

    func play(_ song: Song) throws {
        player = try AVAudioPlayer(contentsOf: song.url)
        player?.play()
    }

    func pause() {
        player?.pause()
    }
}
