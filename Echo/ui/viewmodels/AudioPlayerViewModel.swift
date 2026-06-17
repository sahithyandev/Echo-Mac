import Foundation
import Combine

@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var nowPlaying: Song?

    private let player = AudioPlayer()

    func play(_ song: Song) {
        do {
            try player.play(song)
            nowPlaying = song
        } catch {
            print("Error playing \(song.title): \(error)")
        }
    }

    func pause() {
        player.pause()
    }
}
