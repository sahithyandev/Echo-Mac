import Foundation
import SQLite3

struct SongStat {
    // song_id: chromaprint stableId when available, filename fallback for pre-fingerprint songs
    let id: String
    let title: String
    let plays: Int
    let skips: Int
    let completions: Int
}

// ponytail: raw SQLite3 (built into OS), no GRDB/SQLite.swift dep needed
enum PlaybackStore {
    // .utility, not .background: main-thread reads queue.sync onto this queue, and
    // .background is I/O-throttled by the kernel — a classic priority-inversion stall.
    private static let queue = DispatchQueue(label: "echo.playback", qos: .utility)
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // ponytail: DateFormatter reused; local calendar so day boundaries match the user's timezone
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // Test seam: set before reading test results to point PlaybackStore at an isolated
    // temp DB. Tests run hosted inside Echo.app (TEST_HOST), so the app's own launch
    // sequence can touch the real on-disk DB first — the didSet forces a reopen at the
    // new path rather than relying on being first, which a plain lazy static can't do.
    static var dbPathOverride: String? {
        didSet {
            guard dbPathOverride != oldValue else { return }
            queue.sync {
                if let existing = cachedDB { sqlite3_close(existing) }
                cachedDB = openDB(override: dbPathOverride)
            }
        }
    }

    private static var cachedDB: OpaquePointer? = openDB(override: dbPathOverride)
    private static var db: OpaquePointer? { cachedDB }

    private static func openDB(override: String?) -> OpaquePointer? {
        let path: String
        var oldAnalyticsPath: String?
        if let override {
            path = override
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = support.appendingPathComponent("Echo")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = dir.appendingPathComponent("playback.db").path
            oldAnalyticsPath = dir.appendingPathComponent("analytics.db").path
        }
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK,
              let db = handle else { return nil }

        for sql in [
            // WAL + NORMAL: writers don't block readers, and frequent event/listening
            // inserts skip the per-commit full fsync (WAL is still crash-safe at NORMAL).
            "PRAGMA journal_mode=WAL",
            "PRAGMA synchronous=NORMAL",
            // songs: one row per stable identity; artist/album/year/genre enable direct SQL grouping
            """
            CREATE TABLE IF NOT EXISTS songs (
                id     TEXT PRIMARY KEY,
                title  TEXT NOT NULL,
                artist TEXT,
                album  TEXT,
                year   INTEGER,
                genre  TEXT
            )
            """,
            // song_paths: reverse-lookup id → file locations (migrated rows use filename; new rows use full path)
            // ponytail: INSERT OR IGNORE so collisions (same filename, different dirs) silently keep first entry
            """
            CREATE TABLE IF NOT EXISTS song_paths (
                path    TEXT PRIMARY KEY,
                song_id TEXT NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_song_paths_song ON song_paths(song_id)",
            """
            CREATE TABLE IF NOT EXISTS events (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                song_id   TEXT NOT NULL,
                event     TEXT NOT NULL,
                progress  REAL NOT NULL,
                timestamp REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_events_song  ON events(song_id)",
            "CREATE INDEX IF NOT EXISTS idx_events_event ON events(event)",
            """
            CREATE TABLE IF NOT EXISTS listening (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                song_id   TEXT NOT NULL,
                seconds   REAL NOT NULL,
                day       TEXT NOT NULL,
                timestamp REAL NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_listening_song ON listening(song_id)",
            "CREATE INDEX IF NOT EXISTS idx_listening_day  ON listening(day)",
        ] {
            sqlite3_exec(db, sql, nil, nil, nil)
        }

        // ponytail: user_version=1 gates the one-shot migration from analytics.db; retries on failure (version stays 0)
        var userVersion: Int32 = 0
        var vStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &vStmt, nil) == SQLITE_OK,
           sqlite3_step(vStmt) == SQLITE_ROW {
            userVersion = sqlite3_column_int(vStmt, 0)
        }
        sqlite3_finalize(vStmt)

        if userVersion == 0 {
            if let oldPath = oldAnalyticsPath, FileManager.default.fileExists(atPath: oldPath) {
                // ATTACH can't be inside a transaction, so attach first, then wrap copies in BEGIN/COMMIT
                let escaped = oldPath.replacingOccurrences(of: "'", with: "''")
                var ok = sqlite3_exec(db, "ATTACH '\(escaped)' AS old", nil, nil, nil) == SQLITE_OK
                ok = ok && sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK
                ok = ok && sqlite3_exec(db, """
                    INSERT OR IGNORE INTO songs(id, title)
                    SELECT id, MAX(title) FROM (
                        SELECT COALESCE(stable_id, song_path) AS id, title FROM old.events
                        UNION ALL
                        SELECT COALESCE(stable_id, song_path) AS id, title FROM old.listening
                    ) GROUP BY id
                """, nil, nil, nil) == SQLITE_OK
                ok = ok && sqlite3_exec(db, """
                    INSERT INTO events(song_id, event, progress, timestamp)
                    SELECT COALESCE(stable_id, song_path), event, progress, timestamp FROM old.events
                """, nil, nil, nil) == SQLITE_OK
                ok = ok && sqlite3_exec(db, """
                    INSERT INTO listening(song_id, seconds, day, timestamp)
                    SELECT COALESCE(stable_id, song_path), seconds, day, timestamp FROM old.listening
                """, nil, nil, nil) == SQLITE_OK
                ok = ok && sqlite3_exec(db, """
                    INSERT OR IGNORE INTO song_paths(path, song_id)
                    SELECT song_path, COALESCE(stable_id, song_path)
                    FROM (
                        SELECT DISTINCT song_path, stable_id FROM old.events
                        UNION
                        SELECT DISTINCT song_path, stable_id FROM old.listening
                    )
                """, nil, nil, nil) == SQLITE_OK

                if ok {
                    sqlite3_exec(db, "COMMIT", nil, nil, nil)
                    sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil)
                    sqlite3_exec(db, "DETACH old", nil, nil, nil)
                    try? FileManager.default.removeItem(atPath: oldPath)
                } else {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    sqlite3_exec(db, "DETACH old", nil, nil, nil)
                    // user_version stays 0 → retries next launch
                }
            } else {
                // Fresh install — no migration needed, mark schema as current
                sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil)
            }
        }

        // v2: library_id on events/listening, for per-library stats scoping. Nullable —
        // pre-existing rows stay unscoped and only surface in the combined ("All") view.
        var schemaVersion: Int32 = 0
        var svStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &svStmt, nil) == SQLITE_OK,
           sqlite3_step(svStmt) == SQLITE_ROW {
            schemaVersion = sqlite3_column_int(svStmt, 0)
        }
        sqlite3_finalize(svStmt)
        if schemaVersion == 1 {
            sqlite3_exec(db, "ALTER TABLE events ADD COLUMN library_id TEXT", nil, nil, nil)
            sqlite3_exec(db, "ALTER TABLE listening ADD COLUMN library_id TEXT", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA user_version = 2", nil, nil, nil)
        }

        return db
    }

    // MARK: - Writes

    static func track(event: String, songId: String, progress: Double, libraryId: String? = nil) {
        let p = round(progress * 1000) / 1000
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO events(song_id,event,progress,timestamp,library_id) VALUES(?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songId, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, event,  -1, TRANSIENT)
            sqlite3_bind_double(stmt, 3, p)
            sqlite3_bind_double(stmt, 4, ts)
            if let libraryId { sqlite3_bind_text(stmt, 5, libraryId, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static func logListening(songId: String, seconds: Double, libraryId: String? = nil) {
        guard seconds > 0 else { return }
        let day = dayFormatter.string(from: Date())
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO listening(song_id,seconds,day,timestamp,library_id) VALUES(?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songId,  -1, TRANSIENT)
            sqlite3_bind_double(stmt, 2, seconds)
            sqlite3_bind_text(stmt, 3, day,     -1, TRANSIENT)
            sqlite3_bind_double(stmt, 4, ts)
            if let libraryId { sqlite3_bind_text(stmt, 5, libraryId, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Upsert a song's dimension data. Overwrites all fields including title (call at play time with authoritative data).
    static func upsertSong(id: String, title: String, artist: String? = nil, album: String? = nil,
                           year: Int? = nil, genre: String? = nil) {
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                INSERT INTO songs(id,title,artist,album,year,genre) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    artist=COALESCE(excluded.artist, songs.artist),
                    album =COALESCE(excluded.album,  songs.album),
                    year  =COALESCE(excluded.year,   songs.year),
                    genre =COALESCE(excluded.genre,  songs.genre)
            """, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, id,    -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, title, -1, TRANSIENT)
            if let a = artist { sqlite3_bind_text(stmt, 3, a, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 3) }
            if let a = album  { sqlite3_bind_text(stmt, 4, a, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
            if let y = year   { sqlite3_bind_int(stmt,  5, Int32(y)) }         else { sqlite3_bind_null(stmt, 5) }
            if let g = genre  { sqlite3_bind_text(stmt, 6, g, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 6) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Register a file path → song_id mapping. INSERT OR IGNORE so re-registration is a no-op.
    static func addPath(_ path: String, songId: String) {
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT OR IGNORE INTO song_paths(path,song_id) VALUES(?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, path,   -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, songId, -1, TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Repoint all rows written under the filename key to the canonical stableId.
    /// Called once per song when the async fingerprint resolves. No-op if they're already equal.
    static func reconcile(filename: String, to stableId: String) {
        guard filename != stableId else { return }
        queue.async {
            guard let db else { return }
            for table in ["events", "listening", "song_paths"] {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db,
                    "UPDATE \(table) SET song_id=? WHERE song_id=?",
                    -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, stableId, -1, TRANSIENT)
                    sqlite3_bind_text(stmt, 2, filename, -1, TRANSIENT)
                    sqlite3_step(stmt); sqlite3_finalize(stmt)
                }
            }
            // Clean up the orphaned filename-keyed songs placeholder row
            var del: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM songs WHERE id=?", -1, &del, nil) == SQLITE_OK {
                sqlite3_bind_text(del, 1, filename, -1, TRANSIENT)
                sqlite3_step(del); sqlite3_finalize(del)
            }
        }
    }

    /// Populate artist/album/year/genre for songs in the DB from the feature store.
    /// Preserves existing title and does not overwrite non-null metadata with null.
    /// Call at launch after featureStore.load() so migrated songs show up in grouped stats.
    static func backfillSongMetadata(_ features: [TrackFeatures]) {
        guard !features.isEmpty else { return }
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                INSERT INTO songs(id,title,artist,album,year,genre) VALUES(?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    artist=COALESCE(excluded.artist, songs.artist),
                    album =COALESCE(excluded.album,  songs.album),
                    year  =COALESCE(excluded.year,   songs.year),
                    genre =COALESCE(excluded.genre,  songs.genre)
            """, -1, &stmt, nil) == SQLITE_OK else { return }
            for f in features {
                let sid   = f.stableId ?? f.songURL.lastPathComponent
                let title = f.songURL.deletingPathExtension().lastPathComponent
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, sid,   -1, TRANSIENT)
                sqlite3_bind_text(stmt, 2, title, -1, TRANSIENT)
                if let a = f.artist { sqlite3_bind_text(stmt, 3, a, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 3) }
                if let a = f.album  { sqlite3_bind_text(stmt, 4, a, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
                if let y = f.year   { sqlite3_bind_int(stmt,  5, Int32(y)) }         else { sqlite3_bind_null(stmt, 5) }
                if let g = f.genre  { sqlite3_bind_text(stmt, 6, g, -1, TRANSIENT) } else { sqlite3_bind_null(stmt, 6) }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    /// Tags legacy events/listening rows (recorded before multi-library support existed,
    /// so library_id is NULL) by matching each row's song back to a full file path in
    /// song_paths and checking which configured library folder it falls under. Idempotent
    /// (only touches NULL rows) and safe to call on every launch/library-list change — it's
    /// how existing users' listening history gets attributed to a library after the upgrade.
    /// Rows whose only known path is a bare filename (very old migrated data) can't be
    /// located and stay unscoped — they still show up in the combined ("All") view.
    static func backfillLibraryIds(libraries: [Library]) {
        guard !libraries.isEmpty else { return }
        // Longest path first so a nested library wins over a parent one it's inside of.
        let sorted = libraries.sorted { $0.path.count > $1.path.count }
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT path, song_id FROM song_paths", -1, &stmt, nil) == SQLITE_OK else { return }
            var songToLibrary: [String: String] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(stmt, 0))
                guard path.contains("/") else { continue } // bare filename fallback row — can't locate
                let songId = String(cString: sqlite3_column_text(stmt, 1))
                if let library = sorted.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
                    songToLibrary[songId] = library.id
                }
            }
            sqlite3_finalize(stmt)
            guard !songToLibrary.isEmpty else { return }

            for table in ["events", "listening"] {
                var upd: OpaquePointer?
                guard sqlite3_prepare_v2(db,
                    "UPDATE \(table) SET library_id=? WHERE song_id=? AND library_id IS NULL",
                    -1, &upd, nil) == SQLITE_OK else { continue }
                for (songId, libraryId) in songToLibrary {
                    sqlite3_reset(upd)
                    sqlite3_bind_text(upd, 1, libraryId, -1, TRANSIENT)
                    sqlite3_bind_text(upd, 2, songId,    -1, TRANSIENT)
                    sqlite3_step(upd)
                }
                sqlite3_finalize(upd)
            }
        }
    }

    // MARK: - Reads

    // Returns (today, week, allTime) totals in seconds. `libraryId` nil = combined across all libraries.
    static func listeningTotals(libraryId: String? = nil) -> (today: Double, week: Double, allTime: Double) {
        let today = dayFormatter.string(from: Date())
        let weekStart = dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return queue.sync {
            guard let db else { return (0, 0, 0) }
            var stmt: OpaquePointer?
            let clause = libraryId != nil ? "WHERE library_id = ?" : ""
            guard sqlite3_prepare_v2(db, """
                SELECT
                    SUM(seconds),
                    SUM(CASE WHEN day = ?  THEN seconds ELSE 0 END),
                    SUM(CASE WHEN day >= ? THEN seconds ELSE 0 END)
                FROM listening
                \(clause)
            """, -1, &stmt, nil) == SQLITE_OK else { return (0, 0, 0) }
            sqlite3_bind_text(stmt, 1, today,     -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, weekStart, -1, TRANSIENT)
            if let libraryId { sqlite3_bind_text(stmt, 3, libraryId, -1, TRANSIENT) }
            var result = (today: 0.0, week: 0.0, allTime: 0.0)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = (
                    today:   sqlite3_column_double(stmt, 1),
                    week:    sqlite3_column_double(stmt, 2),
                    allTime: sqlite3_column_double(stmt, 0)
                )
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    // `libraryId` nil = combined across all libraries.
    static func listeningByDay(libraryId: String? = nil) -> [(day: String, seconds: Double)] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let clause = libraryId != nil ? "WHERE library_id = ?" : ""
            guard sqlite3_prepare_v2(db,
                "SELECT day, SUM(seconds) FROM listening \(clause) GROUP BY day ORDER BY day DESC LIMIT 30",
                -1, &stmt, nil) == SQLITE_OK else { return [] }
            if let libraryId { sqlite3_bind_text(stmt, 1, libraryId, -1, TRANSIENT) }
            var rows: [(day: String, seconds: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append((
                    day:     String(cString: sqlite3_column_text(stmt, 0)),
                    seconds: sqlite3_column_double(stmt, 1)
                ))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    // Per-song daily seconds for the last `days` days, zero-filled (oldest → newest).
    static func listeningDaysBySong(days: Int = 14) -> [String: [Double]] {
        let today = Date()
        let cal = Calendar.current
        let dayKeys: [String] = (0..<days).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { dayFormatter.string(from: $0) }
        }
        guard let oldest = dayKeys.first else { return [:] }
        return queue.sync {
            guard let db else { return [:] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT song_id, day, SUM(seconds)
                FROM listening WHERE day >= ?
                GROUP BY song_id, day
            """, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            sqlite3_bind_text(stmt, 1, oldest, -1, TRANSIENT)
            var raw: [String: [String: Double]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id   = String(cString: sqlite3_column_text(stmt, 0))
                let day  = String(cString: sqlite3_column_text(stmt, 1))
                let secs = sqlite3_column_double(stmt, 2)
                raw[id, default: [:]][day] = secs
            }
            sqlite3_finalize(stmt)
            return raw.mapValues { dayMap in dayKeys.map { dayMap[$0] ?? 0.0 } }
        }
    }

    // ponytail: simple engagement-vs-skip ratio; revisit with recency decay if taste drifts
    static func likeabilityScores() -> [String: Double] {
        queue.sync {
            guard let db else { return [:] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT song_id,
                    COUNT(CASE WHEN event='complete'      THEN 1 END) * 1.00 +
                    COUNT(CASE WHEN event='milestone_75'  THEN 1 END) * 0.75 +
                    COUNT(CASE WHEN event='milestone_50'  THEN 1 END) * 0.50 +
                    COUNT(CASE WHEN event='milestone_25'  THEN 1 END) * 0.25 AS engagement,
                    COUNT(CASE WHEN event='skip'          THEN 1 END) AS dislikes
                FROM events GROUP BY song_id
            """, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            var scores: [String: Double] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id  = String(cString: sqlite3_column_text(stmt, 0))
                let eng = sqlite3_column_double(stmt, 1)
                let dis = sqlite3_column_double(stmt, 2)
                scores[id] = (eng + dis) > 0 ? eng / (eng + dis) : 0.5
            }
            sqlite3_finalize(stmt)
            return scores
        }
    }

    /// Returns song_ids played within the last `songCount` play events OR `hours` hours (whichever is broader).
    static func recentlyPlayedSongIds(songCount: Int = 20, hours: Double = 2) -> Set<String> {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let cutoff = Date().timeIntervalSince1970 - hours * 3600
            guard sqlite3_prepare_v2(db, """
                SELECT DISTINCT song_id FROM events WHERE event='play'
                AND (
                    timestamp >= \(cutoff)
                    OR song_id IN (
                        SELECT song_id FROM events WHERE event='play'
                        ORDER BY timestamp DESC LIMIT \(songCount)
                    )
                )
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var ids = Set<String>()
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
            return ids
        }
    }

    /// Returns the song_id (stableId or filename fallback) of the most recently played song.
    // `libraryId` nil = most recent play across all libraries.
    static func lastPlayedSongId(libraryId: String? = nil) -> String? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            let clause = libraryId != nil ? "AND library_id = ?" : ""
            guard sqlite3_prepare_v2(db,
                "SELECT song_id FROM events WHERE event='play' \(clause) ORDER BY timestamp DESC LIMIT 1",
                -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            if let libraryId { sqlite3_bind_text(stmt, 1, libraryId, -1, TRANSIENT) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    static func songStats() -> [SongStat] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT e.song_id, COALESCE(s.title, e.song_id),
                    COUNT(CASE WHEN e.event='play'     THEN 1 END),
                    COUNT(CASE WHEN e.event='skip'     THEN 1 END),
                    COUNT(CASE WHEN e.event='complete' THEN 1 END)
                FROM events e LEFT JOIN songs s ON s.id = e.song_id
                GROUP BY e.song_id ORDER BY 3 DESC
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var rows: [SongStat] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SongStat(
                    id:          String(cString: sqlite3_column_text(stmt, 0)),
                    title:       String(cString: sqlite3_column_text(stmt, 1)),
                    plays:       Int(sqlite3_column_int(stmt, 2)),
                    skips:       Int(sqlite3_column_int(stmt, 3)),
                    completions: Int(sqlite3_column_int(stmt, 4))
                ))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    // Splits a combined artist tag ("A, B & C") into individual artist names.
    // ponytail: false-positives on names with literal "," or "&" (e.g. "Earth, Wind & Fire");
    // add an allowlist only if that becomes a real problem.
    static func splitArtists(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",&"))
           .map { $0.trimmingCharacters(in: .whitespaces) }
           .filter { !$0.isEmpty }
    }

    // Top groups by song dimension attribute — used by StatsView ranked lists.
    // `libraryId` nil = combined across all libraries.
    static func topByArtist(libraryId: String? = nil) -> [(name: String, seconds: Double)] {
        // Fetch raw per-tag totals, then split and re-aggregate so collaborators
        // (e.g. "A & B") each get credit individually.
        let rawRows: [(artist: String, seconds: Double)] = queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let clause = libraryId != nil ? "AND l.library_id = ?" : ""
            guard sqlite3_prepare_v2(db, """
                SELECT s.artist, SUM(l.seconds) AS total
                FROM listening l JOIN songs s ON s.id = l.song_id
                WHERE s.artist IS NOT NULL AND s.artist <> '' \(clause)
                GROUP BY s.artist
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            if let libraryId { sqlite3_bind_text(stmt, 1, libraryId, -1, TRANSIENT) }
            var rows: [(artist: String, seconds: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append((
                    artist:  String(cString: sqlite3_column_text(stmt, 0)),
                    seconds: sqlite3_column_double(stmt, 1)
                ))
            }
            sqlite3_finalize(stmt)
            return rows
        }
        var totals: [String: Double] = [:]
        for row in rawRows {
            for artist in splitArtists(row.artist) {
                totals[artist, default: 0] += row.seconds
            }
        }
        return totals
            .filter { $0.value >= 3600 }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (name: $0.key, seconds: $0.value) }
    }

    static func topByAlbum(libraryId: String? = nil)  -> [(name: String, seconds: Double)] { topByAttribute("album", libraryId: libraryId)  }
    static func topByYear(libraryId: String? = nil)   -> [(name: String, seconds: Double)] { topByAttribute("year", libraryId: libraryId)   }
    static func topByGenre(libraryId: String? = nil)  -> [(name: String, seconds: Double)] { topByAttribute("genre", libraryId: libraryId)  }

    private static func topByAttribute(_ column: String, libraryId: String? = nil) -> [(name: String, seconds: Double)] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            let clause = libraryId != nil ? "AND l.library_id = ?" : ""
            guard sqlite3_prepare_v2(db, """
                SELECT s.\(column), SUM(l.seconds) AS total
                FROM listening l JOIN songs s ON s.id = l.song_id
                WHERE s.\(column) IS NOT NULL AND s.\(column) <> '' \(clause)
                GROUP BY s.\(column)
                HAVING total >= 3600
                ORDER BY total DESC
                LIMIT 10
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            if let libraryId { sqlite3_bind_text(stmt, 1, libraryId, -1, TRANSIENT) }
            var rows: [(name: String, seconds: Double)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append((
                    name:    String(cString: sqlite3_column_text(stmt, 0)),
                    seconds: sqlite3_column_double(stmt, 1)
                ))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }
}
