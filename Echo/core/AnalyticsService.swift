import Foundation
import SQLite3
import EchoCore

struct SongStat {
    // stable_id when available, filename fallback for pre-migration rows
    let id: String
    let title: String
    let plays: Int
    let skips: Int
    let completions: Int
}

struct ListeningStat {
    // stable_id when available, filename fallback for pre-migration rows
    let id: String
    let title: String
    let seconds: Double
}

// ponytail: raw SQLite3 (built into OS), no GRDB/SQLite.swift dep needed
enum AnalyticsService {
    private static let queue = DispatchQueue(label: "echo.analytics", qos: .background)
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
        var db: OpaquePointer?
        guard sqlite3_open(dir.appendingPathComponent("analytics.db").path, &db) == SQLITE_OK else { return nil }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS events (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                event     TEXT    NOT NULL,
                song_path TEXT    NOT NULL,
                title     TEXT    NOT NULL,
                progress  REAL    NOT NULL,
                timestamp REAL    NOT NULL
            )
        """, nil, nil, nil)
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS listening (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                song_path TEXT    NOT NULL,
                title     TEXT    NOT NULL,
                seconds   REAL    NOT NULL,
                day       TEXT    NOT NULL,
                timestamp REAL    NOT NULL
            )
        """, nil, nil, nil)
        // Additive migration: add stable_id column if not present.
        // sqlite3_exec ignores the error if the column already exists.
        sqlite3_exec(db, "ALTER TABLE events   ADD COLUMN stable_id TEXT", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE listening ADD COLUMN stable_id TEXT", nil, nil, nil)
        return db
    }()

    // MARK: - Writes

    static func track(event: String, song: Song, progress: Double, stableId: String? = nil) {
        let songPath = song.url.lastPathComponent
        let title = song.title
        let p = round(progress * 1000) / 1000
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO events (event,song_path,title,progress,timestamp,stable_id) VALUES (?,?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, event,    -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, songPath, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 3, title,    -1, TRANSIENT)
            sqlite3_bind_double(stmt, 4, p)
            sqlite3_bind_double(stmt, 5, ts)
            if let sid = stableId {
                sqlite3_bind_text(stmt, 6, sid, -1, TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static func logListening(song: Song, seconds: Double, stableId: String? = nil) {
        guard seconds > 0 else { return }
        let songPath = song.url.lastPathComponent
        let title = song.title
        let day = dayFormatter.string(from: Date())
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO listening (song_path,title,seconds,day,timestamp,stable_id) VALUES (?,?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songPath, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, title,    -1, TRANSIENT)
            sqlite3_bind_double(stmt, 3, seconds)
            sqlite3_bind_text(stmt, 4, day,      -1, TRANSIENT)
            sqlite3_bind_double(stmt, 5, ts)
            if let sid = stableId {
                sqlite3_bind_text(stmt, 6, sid, -1, TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Migration

    /// Backfill stable_id for existing rows whose filename matches a known file.
    /// Idempotent — only touches rows where stable_id IS NULL.
    /// Call once at launch after features have been extracted.
    static func backfillStableIds(_ map: [String: String]) {
        guard !map.isEmpty else { return }
        queue.async {
            guard let db else { return }
            for (filename, sid) in map {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db,
                    "UPDATE events   SET stable_id=? WHERE song_path=? AND stable_id IS NULL",
                    -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, sid,      -1, TRANSIENT)
                    sqlite3_bind_text(stmt, 2, filename, -1, TRANSIENT)
                    sqlite3_step(stmt); sqlite3_finalize(stmt)
                }
                if sqlite3_prepare_v2(db,
                    "UPDATE listening SET stable_id=? WHERE song_path=? AND stable_id IS NULL",
                    -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, sid,      -1, TRANSIENT)
                    sqlite3_bind_text(stmt, 2, filename, -1, TRANSIENT)
                    sqlite3_step(stmt); sqlite3_finalize(stmt)
                }
            }
        }
    }

    // MARK: - Reads

    static func listeningBySong() -> [ListeningStat] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT COALESCE(stable_id, song_path), title, SUM(seconds)
                FROM listening GROUP BY COALESCE(stable_id, song_path) ORDER BY 3 DESC
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var rows: [ListeningStat] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ListeningStat(
                    id:      String(cString: sqlite3_column_text(stmt, 0)),
                    title:   String(cString: sqlite3_column_text(stmt, 1)),
                    seconds: sqlite3_column_double(stmt, 2)
                ))
            }
            sqlite3_finalize(stmt)
            return rows
        }
    }

    // Returns (allTime, today, last-7-days) totals in seconds
    static func listeningTotals() -> (today: Double, week: Double, allTime: Double) {
        let today = dayFormatter.string(from: Date())
        let weekStart = dayFormatter.string(from: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return queue.sync {
            guard let db else { return (0, 0, 0) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT
                    SUM(seconds),
                    SUM(CASE WHEN day = ?     THEN seconds ELSE 0 END),
                    SUM(CASE WHEN day >= ?    THEN seconds ELSE 0 END)
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
            guard sqlite3_prepare_v2(db, """
                SELECT day, SUM(seconds) FROM listening GROUP BY day ORDER BY day DESC LIMIT 30
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
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

    // Returns per-song daily listening seconds for the last `days` days,
    // zero-filled so every song's array has exactly `days` entries (oldest → newest).
    // One query covers all songs — callers don't need N separate fetches.
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
                SELECT COALESCE(stable_id, song_path), day, SUM(seconds)
                FROM listening
                WHERE day >= ?
                GROUP BY COALESCE(stable_id, song_path), day
            """, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            sqlite3_bind_text(stmt, 1, oldest, -1, TRANSIENT)

            var raw: [String: [String: Double]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id  = String(cString: sqlite3_column_text(stmt, 0))
                let day = String(cString: sqlite3_column_text(stmt, 1))
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
                SELECT COALESCE(stable_id, song_path),
                    COUNT(CASE WHEN event='complete'        THEN 1 END) * 1.00 +
                    COUNT(CASE WHEN event='milestone_75'   THEN 1 END) * 0.75 +
                    COUNT(CASE WHEN event='milestone_50'   THEN 1 END) * 0.50 +
                    COUNT(CASE WHEN event='milestone_25'   THEN 1 END) * 0.25 AS engagement,
                    COUNT(CASE WHEN event='skip'           THEN 1 END) AS dislikes
                FROM events GROUP BY COALESCE(stable_id, song_path)
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

    /// Returns the stable_id (or filename for pre-migration rows) of the most recently played song.
    static func lastPlayedStableId() -> String? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT COALESCE(stable_id, song_path) FROM events WHERE event='play' ORDER BY timestamp DESC LIMIT 1",
                -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    /// Groups total listening seconds by an arbitrary tag attribute (artist/album/year/genre).
    /// Songs with a nil or empty attribute value are dropped (not bucketed as "Unknown").
    /// ponytail: join key is stable_id (or filename fallback) — content-stable across renames/retags.
    static func topGroups(
        listening: [ListeningStat],
        featureById: [String: TrackFeatures],
        attribute: (TrackFeatures) -> String?
    ) -> [(name: String, seconds: Double)] {
        var totals: [String: Double] = [:]
        for row in listening {
            guard let f = featureById[row.id],
                  let name = attribute(f), !name.isEmpty else { continue }
            totals[name, default: 0] += row.seconds
        }
        return totals.sorted { $0.value > $1.value }.map { (name: $0.key, seconds: $0.value) }
    }

    static func songStats() -> [SongStat] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT COALESCE(stable_id, song_path), title,
                    COUNT(CASE WHEN event='play'     THEN 1 END),
                    COUNT(CASE WHEN event='skip'     THEN 1 END),
                    COUNT(CASE WHEN event='complete' THEN 1 END)
                FROM events GROUP BY COALESCE(stable_id, song_path) ORDER BY 3 DESC
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
}
