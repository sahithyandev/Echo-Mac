import Foundation
import Combine
import AVFoundation

@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var nowPlaying: Song?
    @Published var isPlaying: Bool = false

    private let player = AudioPlayer()
    private var queue: [Song] = []
    private var currentIndex: Int?

    var canPlayPrev: Bool { (currentIndex ?? 0) > 0 }
    var canPlayNext: Bool {
        guard let idx = currentIndex else { return false }
        return idx < queue.count - 1
    }

    func play(_ song: Song, in queue: [Song] = []) {
        if !queue.isEmpty {
            self.queue = queue
            self.currentIndex = queue.firstIndex(where: { $0.id == song.id })
        }
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

    func playNext() {
        guard let idx = currentIndex, idx < queue.count - 1 else { return }
        play(queue[idx + 1])
        currentIndex = idx + 1
    }

    func playPrev() {
        guard let idx = currentIndex, idx > 0 else { return }
        play(queue[idx - 1])
        currentIndex = idx - 1
    }
}
