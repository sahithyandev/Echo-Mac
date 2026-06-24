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
    @Published var isShuffled: Bool = false
    @Published var recommendations: [Song] = []
    private let player = AudioPlayer()
    private let systemControls = NowPlayingService()
    private(set) var queue: [Song] = []
    private var originalQueue: [Song] = []
    private var currentIndex: Int?

    // song_id for the currently-playing song (filename until fingerprint resolves, then stableId).
    private var nowPlayingSongId: String?

    private let featureStore: FeatureStore = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Echo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FeatureStore(storeURL: dir.appendingPathComponent("features.json"))
    }()
    private let featureExtractor = FeatureExtractor()
    private let similarityEngine = SimilarityEngine()
    private var progressTimer: Timer?
    private var lastSongCompleted = false
    private var trackedMilestones = Set<Int>()
    // Wakatime-style: diff the engine's clock each tick; only real playback advances it
    private var listenAnchor: TimeInterval = 0
    private var listenAccrued: Double = 0

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
            self.flushListening()
            if let song = self.nowPlaying {
                let sid = await self.featureStore.features(for: song.url)?.stableId
                PlaybackStore.track(event: "complete", songId: sid ?? song.url.lastPathComponent, progress: 1.0)
            }
            self.playNext()
        }
    }

    func play(_ song: Song, in queue: [Song] = []) {
        flushListening()
        if let current = nowPlaying, !lastSongCompleted {
            PlaybackStore.track(event: "skip", songId: nowPlayingSongId ?? current.url.lastPathComponent, progress: progress)
        }
        lastSongCompleted = false

        // Set song_id to filename immediately so the play event and early listen rows have a valid key.
        // The async Task below promotes it to the stableId once the fingerprint resolves.
        let initialId = song.url.lastPathComponent
        nowPlayingSongId = initialId

        if !queue.isEmpty {
            self.originalQueue = queue
            if isShuffled {
                var rest = queue.filter { $0.id != song.id }
                rest.shuffle()
                self.queue = [song] + rest
                self.currentIndex = 0
            } else {
                self.queue = queue
                self.currentIndex = queue.firstIndex(where: { $0.id == song.id })
            }
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
        PlaybackStore.track(event: "play", songId: initialId, progress: 0.0)
        Task {
            // Resolve stableId asynchronously, then promote song_id and reconcile early rows.
            let features = await featureStore.features(for: song.url)
            if let sid = features?.stableId {
                nowPlayingSongId = sid
                PlaybackStore.upsertSong(id: sid, title: song.title,
                                         artist: features?.artist, album: features?.album,
                                         year: features?.year, genre: features?.genre)
                PlaybackStore.addPath(song.url.path, songId: sid)
                PlaybackStore.reconcile(filename: initialId, to: sid)
            } else {
                // Fingerprint not yet available — register with filename key so metadata is queryable
                PlaybackStore.upsertSong(id: initialId, title: song.title,
                                         artist: features?.artist, album: features?.album,
                                         year: features?.year, genre: features?.genre)
                PlaybackStore.addPath(song.url.path, songId: initialId)
            }
            await refreshRecommendations()
        }
    }

    // Called from Home.onAppear to seed recommendations before anything is playing.
    func loadInitialRecommendations(from songs: [Song]) {
        guard recommendations.isEmpty, nowPlaying == nil else { return }
        Task {
            await featureStore.load()
            await featureStore.ensureFeatures(for: songs.map(\.url), using: featureExtractor)
            let allFeatures = await featureStore.allFeatures()

            // Populate artist/album/year/genre for migrated songs that have no metadata yet in playback.db
            PlaybackStore.backfillSongMetadata(allFeatures)

            let filenameToStableId = Dictionary(
                allFeatures.compactMap { f -> (String, String)? in
                    f.stableId.map { (f.songURL.lastPathComponent, $0) }
                },
                uniquingKeysWith: { a, _ in a }
            )
            guard let lastId = PlaybackStore.lastPlayedSongId() else { return }
            let seed = songs.first(where: { f in
                guard let sid = filenameToStableId[f.url.lastPathComponent] else {
                    return f.url.lastPathComponent == lastId
                }
                return sid == lastId
            })
            guard let seed else { return }
            await computeRecommendations(seed: seed, library: songs)
        }
    }

    private func refreshRecommendations() async {
        guard let seed = nowPlaying else { recommendations = []; return }
        let library = originalQueue
        await featureStore.load()
        await featureStore.ensureFeatures(for: library.map(\.url), using: featureExtractor)
        guard nowPlaying?.id == seed.id else { return }
        await computeRecommendations(seed: seed, library: library)
    }

    private func computeRecommendations(seed: Song, library: [Song]) async {
        guard let seedFeatures = await featureStore.features(for: seed.url) else { return }
        let allFeatures = await featureStore.allFeatures()
        // Pull a larger pool so likeability re-rank has room to work before truncation
        let recs = similarityEngine.recommendations(for: seedFeatures, from: allFeatures, count: 20)
        let like = PlaybackStore.likeabilityScores()
        // Feature store has authoritative ID3 metadata; backfill onto Song in case
        // MusicLibraryViewModel.loadMetadata() hadn't finished when play() was called.
        let featuresByURL = Dictionary(uniqueKeysWithValues: allFeatures.map { ($0.songURL, $0) })
        let urlToSong = Dictionary(uniqueKeysWithValues: library.map { song -> (URL, Song) in
            var s = song
            if let f = featuresByURL[song.url] {
                s.artist = f.artist ?? s.artist
                s.album  = f.album  ?? s.album
            }
            return (s.url, s)
        })
        let updated = recs
            .compactMap { rec -> (song: Song, score: Double)? in
                guard let song = urlToSong[rec.songURL] else { return nil }
                // ponytail: 0.3 likeability nudge; raise toward 0.5 for more personalization
                // Key by stableId when available, filename fallback for pre-fingerprint songs.
                let likeKey   = featuresByURL[rec.songURL]?.stableId ?? rec.songURL.lastPathComponent
                let likeScore = like[likeKey] ?? 0.5
                return (song, 0.7 * rec.similarityScore + 0.3 * likeScore)
            }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map(\.song)
        if !updated.isEmpty { recommendations = updated }
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
            flushListening()
            if let song = nowPlaying {
                PlaybackStore.track(event: "pause", songId: nowPlayingSongId ?? song.url.lastPathComponent, progress: progress)
            }
        } else {
            player.resume()
            isPlaying = true
            if let song = nowPlaying {
                PlaybackStore.track(event: "resume", songId: nowPlayingSongId ?? song.url.lastPathComponent, progress: progress)
            }
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
        listenAnchor = player.currentTime
        listenAccrued = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let duration = self.player.duration
                self.duration = duration
                self.progress = duration > 0 ? self.player.currentTime / duration : 0
                self.timeRemaining = max(0, duration - self.player.currentTime)
                self.updateSystemNowPlaying()
                self.checkMilestones()
                // Accumulate only real playback time: diff the engine clock each tick.
                // Gate: forward-only, under 1.5s (seeks produce large jumps, pauses produce 0).
                let now = self.player.currentTime
                let delta = now - self.listenAnchor
                self.listenAnchor = now
                if self.isPlaying, delta > 0, delta < 1.5 {
                    self.listenAccrued += delta
                    if self.listenAccrued >= 30 { self.flushListening() } // ponytail: flush every 30s; lose ≤30s on crash
                }
            }
        }
    }

    private func checkMilestones() {
        guard let song = nowPlaying else { return }
        let pct = Int(progress * 100)
        for milestone in [25, 50, 75] where pct >= milestone && !trackedMilestones.contains(milestone) {
            trackedMilestones.insert(milestone)
            PlaybackStore.track(event: "milestone_\(milestone)", songId: nowPlayingSongId ?? song.url.lastPathComponent, progress: progress)
        }
    }

    private func flushListening() {
        guard listenAccrued > 0, let song = nowPlaying else { return }
        PlaybackStore.logListening(songId: nowPlayingSongId ?? song.url.lastPathComponent, seconds: listenAccrued)
        listenAccrued = 0
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let current = nowPlaying else { return }
        if isShuffled {
            var rest = originalQueue.filter { $0.id != current.id }
            rest.shuffle()
            queue = [current] + rest
            currentIndex = 0
        } else {
            queue = originalQueue
            currentIndex = originalQueue.firstIndex(where: { $0.id == current.id })
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

    /// Returns all cached TrackFeatures — used by recommendation engine.
    /// Only reads what's already on disk; does not trigger extraction.
    func allFeatures() async -> [TrackFeatures] {
        await featureStore.load()
        return await featureStore.allFeatures()
    }
}
