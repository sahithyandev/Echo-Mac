import Foundation
import Testing
@testable import Echo

@Suite("LocalLibrarySource")
struct LocalLibrarySourceTests {
    @Test("listSongs() recurses into subdirectories")
    func recursesIntoSubdirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("musiclibrary-test-\(UUID())")
        let nested = root.appendingPathComponent("Artist/Album")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: root.appendingPathComponent("top.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("nested.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: nested.appendingPathComponent("ignore.txt").path, contents: Data())

        let songs = try LocalLibrarySource(directory: root).listSongs()

        #expect(songs.map(\.title).sorted() == ["nested", "top"])
    }
}

@Suite("MusicLibraryViewModel — multi-library")
@MainActor
struct MusicLibraryViewModelTests {
    private func tempDefaults() -> UserDefaults {
        let suite = "echo-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("seeds ~/Music when nothing is persisted")
    func seedsDefault() {
        let vm = MusicLibraryViewModel(userDefaults: tempDefaults())
        #expect(vm.libraries.count == 1)
        #expect(vm.libraries.first?.path == "/Users/\(NSUserName())/Music")
    }

    @Test("migrates the legacy single-directory key")
    func migratesLegacyKey() {
        let defaults = tempDefaults()
        defaults.set("/tmp/legacy-library", forKey: "libraryDirectory")
        let vm = MusicLibraryViewModel(userDefaults: defaults)
        #expect(vm.libraries.map(\.path) == ["/tmp/legacy-library"])
    }

    @Test("add persists, dedups by path, and is picked up on relaunch")
    func addPersistsAndDedups() {
        let defaults = tempDefaults()
        let vm = MusicLibraryViewModel(userDefaults: defaults)
        let initialCount = vm.libraries.count

        vm.addLibraries([URL(fileURLWithPath: "/tmp/lib-a"), URL(fileURLWithPath: "/tmp/lib-b")])
        #expect(vm.libraries.count == initialCount + 2)

        // Re-adding the same path is a no-op.
        vm.addLibraries([URL(fileURLWithPath: "/tmp/lib-a")])
        #expect(vm.libraries.count == initialCount + 2)

        // Simulates a relaunch: fresh view model, same UserDefaults.
        let reloaded = MusicLibraryViewModel(userDefaults: defaults)
        #expect(Set(reloaded.libraries.map(\.path)) == Set(vm.libraries.map(\.path)))
    }

    @Test("id is the folder path, and survives remove/re-add unchanged")
    func idIsStablePath() {
        let defaults = tempDefaults()
        let vm = MusicLibraryViewModel(userDefaults: defaults)
        vm.addLibraries([URL(fileURLWithPath: "/tmp/lib-a")])
        let library = vm.libraries.first { $0.path == "/tmp/lib-a" }
        #expect(library?.id == "/tmp/lib-a")

        vm.removeLibrary("/tmp/lib-a")
        vm.addLibraries([URL(fileURLWithPath: "/tmp/lib-a")])
        #expect(vm.libraries.first { $0.path == "/tmp/lib-a" }?.id == "/tmp/lib-a")
    }

    @Test("rename updates the display name, persists, and doesn't change id")
    func renamePersists() {
        let defaults = tempDefaults()
        let vm = MusicLibraryViewModel(userDefaults: defaults)
        vm.addLibraries([URL(fileURLWithPath: "/tmp/lib-a")])
        let id = vm.libraries.first { $0.path == "/tmp/lib-a" }!.id

        vm.renameLibrary(id, to: "My Beats")
        #expect(vm.libraries.first { $0.id == id }?.name == "My Beats")

        // Blank names are rejected — the existing name is kept.
        vm.renameLibrary(id, to: "   ")
        #expect(vm.libraries.first { $0.id == id }?.name == "My Beats")

        let reloaded = MusicLibraryViewModel(userDefaults: defaults)
        #expect(reloaded.libraries.first { $0.id == id }?.name == "My Beats")
    }

    @Test("remove persists and can empty the list entirely")
    func removeCanEmptyList() {
        let defaults = tempDefaults()
        let vm = MusicLibraryViewModel(userDefaults: defaults)
        for library in vm.libraries { vm.removeLibrary(library.id) }
        #expect(vm.libraries.isEmpty)

        let reloaded = MusicLibraryViewModel(userDefaults: defaults)
        #expect(reloaded.libraries.isEmpty)
    }

    @Test("dedupByURL keeps first occurrence and sorts by filename")
    func dedupByURL() {
        let libA = "lib-a", libB = "lib-b"
        var shared = Song(url: URL(fileURLWithPath: "/tmp/shared.mp3"))
        shared.libraryId = libA
        var sharedAgain = Song(url: URL(fileURLWithPath: "/tmp/shared.mp3"))
        sharedAgain.libraryId = libB
        var zTrack = Song(url: URL(fileURLWithPath: "/tmp/zzz.mp3"))
        zTrack.libraryId = libB

        let merged = MusicLibraryViewModel.dedupByURL([zTrack, shared, sharedAgain])

        #expect(merged.count == 2)
        #expect(merged.map(\.title) == ["shared", "zzz"])
        #expect(merged.first?.libraryId == libA) // first occurrence wins
    }
}

// .serialized: every test here mutates the shared PlaybackStore.dbPathOverride/cachedDB
// static state, so running them concurrently races on which temp DB is "current."
@Suite("PlaybackStore", .serialized)
struct PlaybackStoreLibraryScopingTests {
    @Test("listeningTotals and topByArtist scope by library, nil combines all")
    func scoping() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-playback-test-\(UUID()).db").path
        PlaybackStore.dbPathOverride = tempPath
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let libA = "library-a"
        let libB = "library-b"

        PlaybackStore.upsertSong(id: "song-a", title: "Song A", artist: "Artist A")
        PlaybackStore.upsertSong(id: "song-b", title: "Song B", artist: "Artist B")

        PlaybackStore.logListening(songId: "song-a", seconds: 4000, libraryId: libA)
        PlaybackStore.logListening(songId: "song-b", seconds: 5000, libraryId: libB)
        PlaybackStore.logListening(songId: "song-a", seconds: 1000) // legacy row, no library — combined-only

        // Writes are enqueued via queue.async on PlaybackStore's serial queue; reads use
        // queue.sync on the same queue, so by the time we call a read below, everything
        // scheduled above has already run (FIFO on a serial queue).

        let totalsA = PlaybackStore.listeningTotals(libraryId: libA)
        let totalsB = PlaybackStore.listeningTotals(libraryId: libB)
        let totalsCombined = PlaybackStore.listeningTotals()

        #expect(totalsA.allTime == 4000)
        #expect(totalsB.allTime == 5000)
        #expect(totalsCombined.allTime == 10000) // 4000 + 5000 + 1000 legacy row

        let artistsA = PlaybackStore.topByArtist(libraryId: libA)
        #expect(artistsA.map(\.name) == ["Artist A"])

        let artistsCombined = PlaybackStore.topByArtist()
        #expect(Set(artistsCombined.map(\.name)) == ["Artist A", "Artist B"])
    }

    @Test("backfillLibraryIds attributes pre-upgrade listening history by matching file path to library folder")
    func backfillLibraryIds() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-playback-test-\(UUID()).db").path
        PlaybackStore.dbPathOverride = tempPath
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let libA = Library(path: "/tmp/musicA")
        let libB = Library(path: "/tmp/musicB")

        PlaybackStore.upsertSong(id: "song-a", title: "Song A")
        PlaybackStore.upsertSong(id: "song-b", title: "Song B")
        PlaybackStore.upsertSong(id: "song-c", title: "Song C")

        PlaybackStore.addPath("/tmp/musicA/track1.mp3", songId: "song-a")
        PlaybackStore.addPath("/tmp/musicB/track2.mp3", songId: "song-b")
        PlaybackStore.addPath("legacy-filename.mp3", songId: "song-c") // bare filename — unattributable

        // Recorded before library_id existed, so these land as NULL — exactly what a
        // pre-upgrade user's history looks like.
        PlaybackStore.logListening(songId: "song-a", seconds: 100)
        PlaybackStore.logListening(songId: "song-b", seconds: 200)
        PlaybackStore.logListening(songId: "song-c", seconds: 50)

        PlaybackStore.backfillLibraryIds(libraries: [libA, libB])

        #expect(PlaybackStore.listeningTotals(libraryId: libA.id).allTime == 100)
        #expect(PlaybackStore.listeningTotals(libraryId: libB.id).allTime == 200)
        // Unattributable row still counts in the combined view.
        #expect(PlaybackStore.listeningTotals().allTime == 350)
    }

    private func freshDB() -> String {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-playback-test-\(UUID()).db").path
        PlaybackStore.dbPathOverride = tempPath
        return tempPath
    }

    @Test("track records events and songStats aggregates plays/skips/completions")
    func trackAndSongStats() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.upsertSong(id: "song-x", title: "Song X")
        PlaybackStore.track(event: "play", songId: "song-x", progress: 0.0)
        PlaybackStore.track(event: "skip", songId: "song-x", progress: 0.4)
        PlaybackStore.track(event: "play", songId: "song-x", progress: 0.0)
        PlaybackStore.track(event: "complete", songId: "song-x", progress: 1.0)

        let stat = try #require(PlaybackStore.songStats().first { $0.id == "song-x" })
        #expect(stat.title == "Song X")
        #expect(stat.plays == 2)
        #expect(stat.skips == 1)
        #expect(stat.completions == 1)
    }

    @Test("reconcile repoints filename-keyed rows to the resolved stableId")
    func reconcileMovesRows() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.upsertSong(id: "track.mp3", title: "Track")
        PlaybackStore.addPath("/tmp/track.mp3", songId: "track.mp3")
        PlaybackStore.track(event: "play", songId: "track.mp3", progress: 0)
        PlaybackStore.logListening(songId: "track.mp3", seconds: 42)

        PlaybackStore.reconcile(filename: "track.mp3", to: "stable-id-1")

        let stats = PlaybackStore.songStats()
        #expect(stats.contains { $0.id == "stable-id-1" && $0.plays == 1 })
        #expect(!stats.contains { $0.id == "track.mp3" })
        #expect(PlaybackStore.listeningTotals().allTime == 42)
    }

    @Test("reconcile is a no-op when filename already equals the target id")
    func reconcileNoOpWhenEqual() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.upsertSong(id: "same-id", title: "Same")
        PlaybackStore.track(event: "play", songId: "same-id", progress: 0)
        PlaybackStore.reconcile(filename: "same-id", to: "same-id")

        #expect(PlaybackStore.songStats().first { $0.id == "same-id" }?.plays == 1)
    }

    @Test("listeningByDay sums seconds per day and scopes by library")
    func listeningByDay() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let todayFormatter = DateFormatter()
        todayFormatter.dateFormat = "yyyy-MM-dd"
        let today = todayFormatter.string(from: Date())

        PlaybackStore.logListening(songId: "s1", seconds: 100, libraryId: "libA")
        PlaybackStore.logListening(songId: "s2", seconds: 50, libraryId: "libB")

        let rowsAll = PlaybackStore.listeningByDay()
        #expect(rowsAll.first?.day == today)
        #expect(rowsAll.first?.seconds == 150)

        let rowsA = PlaybackStore.listeningByDay(libraryId: "libA")
        #expect(rowsA.first?.seconds == 100)
    }

    @Test("listeningDaysBySong zero-fills a per-song day series, most recent last")
    func listeningDaysBySong() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.logListening(songId: "s1", seconds: 30)

        let series = PlaybackStore.listeningDaysBySong(days: 3)
        let arr = try #require(series["s1"])
        #expect(arr.count == 3)
        #expect(arr.last == 30)
        #expect(arr.dropLast().allSatisfy { $0 == 0 })
    }

    @Test("likeabilityScores computes engagement-vs-skip ratio")
    func likeabilityScores() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.track(event: "complete", songId: "liked", progress: 1.0)
        PlaybackStore.track(event: "skip", songId: "disliked", progress: 0.1)
        PlaybackStore.track(event: "milestone_50", songId: "mixed", progress: 0.5)
        PlaybackStore.track(event: "skip", songId: "mixed", progress: 0.5)

        let scores = PlaybackStore.likeabilityScores()
        #expect(scores["liked"] == 1.0)
        #expect(scores["disliked"] == 0.0)
        #expect(abs((scores["mixed"] ?? -1) - (0.5 / 1.5)) < 0.0001)
    }

    @Test("recentlyPlayedSongIds only considers play events")
    func recentlyPlayedSongIds() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        PlaybackStore.track(event: "play", songId: "played", progress: 0)
        PlaybackStore.track(event: "skip", songId: "skipped-only", progress: 0.1)

        let ids = PlaybackStore.recentlyPlayedSongIds()
        #expect(ids.contains("played"))
        #expect(!ids.contains("skipped-only"))
    }

    @Test("topByAlbum/topByYear/topByGenre respect the 1-hour floor and scope by library")
    func topByAttribute() async throws {
        let tempPath = freshDB()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let libA = "lib-a"
        PlaybackStore.upsertSong(id: "song-1", title: "One", album: "Album A", year: 2020, genre: "Rock")
        PlaybackStore.upsertSong(id: "song-2", title: "Two", album: "Album B", year: 2021, genre: "Jazz")
        PlaybackStore.logListening(songId: "song-1", seconds: 4000, libraryId: libA)
        PlaybackStore.logListening(songId: "song-2", seconds: 1000) // below 3600s floor, excluded everywhere

        #expect(PlaybackStore.topByAlbum().map(\.name) == ["Album A"])
        #expect(PlaybackStore.topByYear().map(\.name) == ["2020"])
        #expect(PlaybackStore.topByGenre().map(\.name) == ["Rock"])

        #expect(PlaybackStore.topByAlbum(libraryId: libA).map(\.name) == ["Album A"])
        #expect(PlaybackStore.topByAlbum(libraryId: "other-lib").isEmpty)
    }
}

@Suite("FeatureExtractor")
struct FeatureExtractorTests {
    @Test("parseKey handles major keys")
    func majorKeys() {
        #expect(FeatureExtractor.parseKey("C")?.pitchClass == 0)
        #expect(FeatureExtractor.parseKey("C")?.isMinor == false)
        #expect(FeatureExtractor.parseKey("C#")?.pitchClass == 1)
        #expect(FeatureExtractor.parseKey("Db")?.pitchClass == 1)
        #expect(FeatureExtractor.parseKey("F#")?.pitchClass == 6)
        #expect(FeatureExtractor.parseKey("Bb")?.pitchClass == 10)
        #expect(FeatureExtractor.parseKey("B")?.pitchClass == 11)
    }

    @Test("parseKey handles minor keys")
    func minorKeys() {
        #expect(FeatureExtractor.parseKey("Am")?.pitchClass == 9)
        #expect(FeatureExtractor.parseKey("Am")?.isMinor == true)
        #expect(FeatureExtractor.parseKey("F#m")?.pitchClass == 6)
        #expect(FeatureExtractor.parseKey("Bbm")?.pitchClass == 10)
        #expect(FeatureExtractor.parseKey("C#m")?.pitchClass == 1)
    }

    @Test("parseKey returns nil for unknown values")
    func unknownKey() {
        #expect(FeatureExtractor.parseKey("") == nil)
        #expect(FeatureExtractor.parseKey("X") == nil)
        #expect(FeatureExtractor.parseKey("o") == nil)
    }

    @Test("parseYear handles plain year, ISO date, and junk")
    func parseYear() {
        #expect(FeatureExtractor.parseYear("2001")       == 2001)
        #expect(FeatureExtractor.parseYear("2001-05-03") == 2001)
        #expect(FeatureExtractor.parseYear("2001-05")    == 2001)
        #expect(FeatureExtractor.parseYear("junk")       == nil)
        #expect(FeatureExtractor.parseYear("")            == nil)
        #expect(FeatureExtractor.parseYear("999")         == nil)   // too short
    }

    @Test("extract throws for non-existent file")
    func extractMissingFile() async {
        let extractor = FeatureExtractor()
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).mp3")
        await #expect(throws: (any Error).self) {
            try await extractor.extract(from: url)
        }
    }

    @Test("computeRMS returns nil for non-existent file")
    func rmsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID()).mp3")
        #expect(FeatureExtractor.computeRMS(url: url) == nil)
    }
}

@Suite("SimilarityEngine")
struct SimilarityEngineTests {
    private let engine = SimilarityEngine()

    private func make(_ path: String, bpm: Double? = nil, key: Int? = nil, mode: Int? = nil,
                      loudness: Double? = nil, duration: Double? = nil,
                      artist: String? = nil, album: String? = nil,
                      year: Int? = nil, genre: String? = nil) -> TrackFeatures {
        var f = TrackFeatures(songURL: URL(fileURLWithPath: path))
        f.tempoEstimate = bpm
        f.key = key
        f.mode = mode
        f.averageLoudness = loudness
        f.durationSeconds = duration
        f.artist = artist
        f.album = album
        f.year = year
        f.genre = genre
        return f
    }

    @Test("identical features produce score of 1")
    func identicalFeatures() {
        let seed = make("/a.mp3", bpm: 128, key: 0, mode: 1, loudness: -14, duration: 200)
        let copy = make("/b.mp3", bpm: 128, key: 0, mode: 1, loudness: -14, duration: 200)
        let results = engine.recommendations(for: seed, from: [seed, copy])
        #expect(results.first?.similarityScore == 1.0)
    }

    @Test("closer BPM ranks higher")
    func closerBPMRanksHigher() {
        let seed  = make("/seed.mp3",  bpm: 128)
        let close = make("/close.mp3", bpm: 130)
        let far   = make("/far.mp3",   bpm: 90)
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        let urls = results.map(\.songURL.lastPathComponent)
        #expect(urls.first == "close.mp3")
    }

    @Test("seed excluded from results")
    func seedExcluded() {
        let seed = make("/seed.mp3", bpm: 128)
        let other = make("/other.mp3", bpm: 128)
        let results = engine.recommendations(for: seed, from: [seed, other])
        #expect(!results.map(\.songURL).contains(seed.songURL))
    }

    @Test("nil features are skipped — score still computed from available features")
    func nilFeaturesSkipped() {
        let seed      = make("/seed.mp3",  bpm: 128, loudness: -14)
        let withKey   = make("/match.mp3", bpm: 128, key: 5, loudness: -14)  // same BPM + loudness
        let noFeature = make("/empty.mp3")                                    // no features
        let results = engine.recommendations(for: seed, from: [seed, withKey, noFeature])
        #expect(results.first?.songURL.lastPathComponent == "match.mp3")
    }

    @Test("same key and mode ranks above different mode")
    func keyModeRanking() {
        let seed     = make("/seed.mp3",   key: 0, mode: 1)
        let sameMode = make("/same.mp3",   key: 0, mode: 1)
        let diffMode = make("/diff.mp3",   key: 0, mode: 0)
        let results = engine.recommendations(for: seed, from: [seed, sameMode, diffMode])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("circular key distance: B and C closer than B and F#")
    func circularKeyDistance() {
        // B = 11, C = 0 → dist = min(11, 1) = 1
        // B = 11, F# = 6 → dist = min(5, 7) = 5
        let seed  = make("/seed.mp3", key: 11)
        let close = make("/c.mp3",    key: 0)   // C — 1 semitone away via octave
        let far   = make("/fs.mp3",   key: 6)   // F# — 5 semitones away
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        #expect(results.first?.songURL.lastPathComponent == "c.mp3")
    }

    @Test("same artist ranks above different artist")
    func artistRanking() {
        let seed      = make("/seed.mp3",  artist: "Radiohead")
        let sameArtist = make("/same.mp3", artist: "Radiohead")
        let diffArtist = make("/diff.mp3", artist: "Coldplay")
        let results = engine.recommendations(for: seed, from: [seed, sameArtist, diffArtist])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("closer year ranks higher")
    func yearRanking() {
        let seed  = make("/seed.mp3",  year: 2000)
        let close = make("/close.mp3", year: 2001)
        let far   = make("/far.mp3",   year: 1985)
        let results = engine.recommendations(for: seed, from: [seed, close, far])
        #expect(results.first?.songURL.lastPathComponent == "close.mp3")
    }

    @Test("same genre ranks above different genre")
    func genreRanking() {
        let seed      = make("/seed.mp3",  genre: "Jazz")
        let sameGenre = make("/same.mp3",  genre: "Jazz")
        let diffGenre = make("/diff.mp3",  genre: "Metal")
        let results = engine.recommendations(for: seed, from: [seed, sameGenre, diffGenre])
        #expect(results.first?.songURL.lastPathComponent == "same.mp3")
    }

    @Test("count is respected")
    func countRespected() {
        let seed = make("/seed.mp3", bpm: 120)
        let library = (1...20).map { make("/s\($0).mp3", bpm: Double(100 + $0)) }
        let results = engine.recommendations(for: seed, from: [seed] + library, count: 5)
        #expect(results.count == 5)
    }
}

@Suite("FeatureStore")
struct FeatureStoreTests {
    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("echocore-test-\(UUID()).json")
    }

    @Test("save and reload persists features")
    func saveAndReload() async throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let songURL = URL(fileURLWithPath: "/tmp/song.mp3")
        var features = TrackFeatures(songURL: songURL)
        features.tempoEstimate = 128.0
        features.averageLoudness = -14.5

        let store = FeatureStore(storeURL: storeURL)
        await store.load()
        try await store.save(features)

        // Fresh store, same path — simulates app relaunch
        let reloaded = FeatureStore(storeURL: storeURL)
        await reloaded.load()
        let result = await reloaded.features(for: songURL)

        #expect(result?.tempoEstimate == 128.0)
        #expect(result?.averageLoudness == -14.5)
    }

    @Test("features returns nil for unknown URL")
    func unknownURL() async {
        let store = FeatureStore(storeURL: tempStoreURL())
        await store.load()
        let result = await store.features(for: URL(fileURLWithPath: "/tmp/unknown.mp3"))
        #expect(result == nil)
    }

    @Test("allFeatures returns saved entries")
    func allFeaturesCount() async throws {
        let storeURL = tempStoreURL()
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let store = FeatureStore(storeURL: storeURL)
        await store.load()

        for i in 0..<3 {
            var f = TrackFeatures(songURL: URL(fileURLWithPath: "/tmp/song\(i).mp3"))
            f.tempoEstimate = Double(120 + i * 10)
            try await store.save(f)
        }

        let all = await store.allFeatures()
        #expect(all.count == 3)
    }
}
