import Foundation
import Combine

@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var nowPlaying: Song?
    @Published var isPlaying: Bool = false

    private let player = AudioPlayer()

    func play(_ song: Song) {
        do {
            try player.play(song)
            nowPlaying = song
            isPlaying = true
        } catch {
            print("Error playing \(song.title): \(error)")
        }
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.resume()
            isPlaying = true
        }
    }
}
