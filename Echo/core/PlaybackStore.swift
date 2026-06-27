import Foundation
import SQLite3
import EchoCore

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
    private static let queue = DispatchQueue(label: "echo.playback", qos: .background)
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // ponytail: DateFormatter reused; local calendar so day boundaries match the user's timezone
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let db: OpaquePointer? = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Echo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(dir.appendingPathComponent("playback.db").path, &handle) == SQLITE_OK,
              let db = handle else { return nil }

        for sql in [
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
            let oldPath = dir.appendingPathComponent("analytics.db").path
            if FileManager.default.fileExists(atPath: oldPath) {
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

        return db
    }()

    // MARK: - Writes

    static func track(event: String, songId: String, progress: Double) {
        let p = round(progress * 1000) / 1000
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO events(song_id,event,progress,timestamp) VALUES(?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songId, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, event,  -1, TRANSIENT)
            sqlite3_bind_double(stmt, 3, p)
            sqlite3_bind_double(stmt, 4, ts)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static func logListening(songId: String, seconds: Double) {
        guard seconds > 0 else { return }
        let day = dayFormatter.string(from: Date())
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO listening(song_id,seconds,day,timestamp) VALUES(?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songId,  -1, TRANSIENT)
            sqlite3_bind_double(stmt, 2, seconds)
            sqlite3_bind_text(stmt, 3, day,     -1, TRANSIENT)
            sqlite3_bind_double(stmt, 4, ts)
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

    // MARK: - Reads

    // Returns (today, week, allTime) totals in seconds
    static func listeningTotals() -> (today: Double, week: Double, allTime: Double) {
        let today = dayFormatter.string(from: Date())
        let weekStart = dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return queue.sync {
            guard let db else { return (0, 0, 0) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT
                    SUM(seconds),
                    SUM(CASE WHEN day = ?  THEN seconds ELSE 0 END),
                    SUM(CASE WHEN day >= ? THEN seconds ELSE 0 END)
                FROM listening
            """, -1, &stmt, nil) == SQLITE_OK else { return (0, 0, 0) }
            sqlite3_bind_text(stmt, 1, today,     -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, weekStart, -1, TRANSIENT)
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

    static func listeningByDay() -> [(day: String, seconds: Double)] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT day, SUM(seconds) FROM listening GROUP BY day ORDER BY day DESC LIMIT 30",
                -1, &stmt, nil) == SQLITE_OK else { return [] }
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
    static func lastPlayedSongId() -> String? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT song_id FROM events WHERE event='play' ORDER BY timestamp DESC LIMIT 1",
                -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
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

    static func libraryCounts() -> (songs: Int, artists: Int, albums: Int) {
        queue.sync {
            guard let db else { return (0, 0, 0) }
            var songs = 0, albums = 0
            var artistTags: [String] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, """
                SELECT
                    COUNT(*),
                    COUNT(DISTINCT CASE WHEN album IS NOT NULL AND album <> '' THEN album END)
                FROM songs
            """, -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
                songs  = Int(sqlite3_column_int(stmt, 0))
                albums = Int(sqlite3_column_int(stmt, 1))
            }
            sqlite3_finalize(stmt)
            var aStmt: OpaquePointer?
            if sqlite3_prepare_v2(db,
                "SELECT artist FROM songs WHERE artist IS NOT NULL AND artist <> ''",
                -1, &aStmt, nil) == SQLITE_OK {
                while sqlite3_step(aStmt) == SQLITE_ROW {
                    artistTags.append(String(cString: sqlite3_column_text(aStmt, 0)))
                }
            }
            sqlite3_finalize(aStmt)
            let distinctArtists = Set(artistTags.flatMap { splitArtists($0) })
            return (songs, distinctArtists.count, albums)
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
    static func topByArtist() -> [(name: String, seconds: Double)] {
        // Fetch raw per-tag totals, then split and re-aggregate so collaborators
        // (e.g. "A & B") each get credit individually.
        let rawRows: [(artist: String, seconds: Double)] = queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT s.artist, SUM(l.seconds) AS total
                FROM listening l JOIN songs s ON s.id = l.song_id
                WHERE s.artist IS NOT NULL AND s.artist <> ''
                GROUP BY s.artist
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
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

    static func topByAlbum()  -> [(name: String, seconds: Double)] { topByAttribute("album")  }
    static func topByYear()   -> [(name: String, seconds: Double)] { topByAttribute("year")   }
    static func topByGenre()  -> [(name: String, seconds: Double)] { topByAttribute("genre")  }

    private static func topByAttribute(_ column: String) -> [(name: String, seconds: Double)] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT s.\(column), SUM(l.seconds) AS total
                FROM listening l JOIN songs s ON s.id = l.song_id
                WHERE s.\(column) IS NOT NULL AND s.\(column) <> ''
                GROUP BY s.\(column)
                HAVING total >= 3600
                ORDER BY total DESC
                LIMIT 10
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
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
