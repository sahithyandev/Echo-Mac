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
    private(set) var queue: [Song] = []
    private var currentIndex: Int?
    private var progressTimer: Timer?
    private var lastSongCompleted = false
    private var trackedMilestones = Set<Int>()

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
        Task { @MainActor in
            self.lastSongCompleted = true
            if let song = self.nowPlaying {
                AnalyticsService.track(event: "complete", song: song, progress: 1.0)
            }
            self.playNext()
        }
    }

    func play(_ song: Song, in queue: [Song] = []) {
        if let current = nowPlaying, !lastSongCompleted {
            AnalyticsService.track(event: "skip", song: current, progress: progress)
        }
        lastSongCompleted = false

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
        AnalyticsService.track(event: "play", song: song, progress: 0.0)
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
            if let song = nowPlaying { AnalyticsService.track(event: "pause", song: song, progress: progress) }
        } else {
            player.resume()
            isPlaying = true
            if let song = nowPlaying { AnalyticsService.track(event: "resume", song: song, progress: progress) }
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
        trackedMilestones = []
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let duration = self.player.duration
                self.duration = duration
                self.progress = duration > 0 ? self.player.currentTime / duration : 0
                self.timeRemaining = max(0, duration - self.player.currentTime)
                self.updateSystemNowPlaying()
                self.checkMilestones()
            }
        }
    }

    private func checkMilestones() {
        guard let song = nowPlaying else { return }
        let pct = Int(progress * 100)
        for milestone in [25, 50, 75] where pct >= milestone && !trackedMilestones.contains(milestone) {
            trackedMilestones.insert(milestone)
            AnalyticsService.track(event: "milestone_\(milestone)", song: song, progress: progress)
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
