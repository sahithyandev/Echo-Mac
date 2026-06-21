import Foundation
import Combine
import AVFoundation
import EchoCore

@MainActor
class AudioPlayerViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var nowPlaying: Song?
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private let player = AudioPlayer()
    private let systemControls = NowPlayingService()
    private var queue: [Song] = []
    private var currentIndex: Int?
    private var progressTimer: Timer?

    #if DEBUG
    @Published var debugFeatures: TrackFeatures?
    private let featureExtractor = FeatureExtractor()
    #endif

    var canPlayPrev: Bool { (currentIndex ?? 0) > 0 }
    var canPlayNext: Bool {
        guard let idx = currentIndex else { return false }
        return idx < queue.count - 1
    }

    override init() {
        super.init()
        player.delegate = self
        systemControls.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        systemControls.onNext = { [weak self] in self?.playNext() }
        systemControls.onPrev = { [weak self] in self?.playPrev() }
        systemControls.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        Task { @MainActor in self.playNext() }
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
            startProgressTimer()
            updateSystemNowPlaying()
        } catch {
            print("Error playing \(song.title): \(error)")
        }
        #if DEBUG
        debugFeatures = nil
        let url = song.url
        Task {
            debugFeatures = try? await featureExtractor.extract(from: url)
        }
        #endif
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.resume()
            isPlaying = true
        }
        updateSystemNowPlaying()
    }

    func seek(to time: TimeInterval) {
        player.seek(to: time)
        let dur = player.duration
        progress = dur > 0 ? time / dur : 0
        timeRemaining = max(0, dur - time)
        updateSystemNowPlaying()
    }

    private func updateSystemNowPlaying() {
        guard let song = nowPlaying else {
            systemControls.clear()
            return
        }
        systemControls.update(song: song, currentTime: player.currentTime, duration: player.duration, isPlaying: isPlaying)
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progress = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let duration = self.player.duration
                self.duration = duration
                self.progress = duration > 0 ? self.player.currentTime / duration : 0
                self.timeRemaining = max(0, duration - self.player.currentTime)
                self.updateSystemNowPlaying()
            }
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
