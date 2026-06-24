import Foundation
import SQLite3
import EchoCore

struct SongStat {
    let songPath: String
    let title: String
    let plays: Int
    let skips: Int
    let completions: Int
}

struct ListeningStat {
    let songPath: String
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
        return db
    }()

    static func track(event: String, song: Song, progress: Double) {
        let songPath = song.url.lastPathComponent
        let title = song.title
        let p = round(progress * 1000) / 1000
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO events (event,song_path,title,progress,timestamp) VALUES (?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, event,    -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, songPath, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 3, title,    -1, TRANSIENT)
            sqlite3_bind_double(stmt, 4, p)
            sqlite3_bind_double(stmt, 5, ts)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static func logListening(song: Song, seconds: Double) {
        guard seconds > 0 else { return }
        let songPath = song.url.lastPathComponent
        let title = song.title
        let day = dayFormatter.string(from: Date())
        let ts = Date().timeIntervalSince1970
        queue.async {
            guard let db else { return }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "INSERT INTO listening (song_path,title,seconds,day,timestamp) VALUES (?,?,?,?,?)",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, songPath, -1, TRANSIENT)
            sqlite3_bind_text(stmt, 2, title,    -1, TRANSIENT)
            sqlite3_bind_double(stmt, 3, seconds)
            sqlite3_bind_text(stmt, 4, day,      -1, TRANSIENT)
            sqlite3_bind_double(stmt, 5, ts)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    static func listeningBySong() -> [ListeningStat] {
        queue.sync {
            guard let db else { return [] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT song_path, title, SUM(seconds)
                FROM listening GROUP BY song_path ORDER BY 3 DESC
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var rows: [ListeningStat] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(ListeningStat(
                    songPath: String(cString: sqlite3_column_text(stmt, 0)),
                    title:    String(cString: sqlite3_column_text(stmt, 1)),
                    seconds:  sqlite3_column_double(stmt, 2)
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
        // Build the ordered list of day-string buckets (oldest first)
        let dayKeys: [String] = (0..<days).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { dayFormatter.string(from: $0) }
        }
        guard let oldest = dayKeys.first else { return [:] }

        return queue.sync {
            guard let db else { return [:] }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, """
                SELECT song_path, day, SUM(seconds)
                FROM listening
                WHERE day >= ?
                GROUP BY song_path, day
            """, -1, &stmt, nil) == SQLITE_OK else { return [:] }
            sqlite3_bind_text(stmt, 1, oldest, -1, TRANSIENT)

            // raw[songPath][day] = seconds
            var raw: [String: [String: Double]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(stmt, 0))
                let day  = String(cString: sqlite3_column_text(stmt, 1))
                let secs = sqlite3_column_double(stmt, 2)
                raw[path, default: [:]][day] = secs
            }
            sqlite3_finalize(stmt)

            // Pivot: fill zeros for days with no listening so arrays are fixed-length
            return raw.mapValues { dayMap in dayKeys.map { dayMap[$0] ?? 0.0 } }
        }
    }

    static func lastPlayedSongPath() -> String? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "SELECT song_path FROM events WHERE event='play' ORDER BY timestamp DESC LIMIT 1",
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
                SELECT song_path, title,
                    COUNT(CASE WHEN event='play'     THEN 1 END),
                    COUNT(CASE WHEN event='skip'     THEN 1 END),
                    COUNT(CASE WHEN event='complete' THEN 1 END)
                FROM events GROUP BY song_path ORDER BY 3 DESC
            """, -1, &stmt, nil) == SQLITE_OK else { return [] }
            var rows: [SongStat] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(SongStat(
                    songPath:    String(cString: sqlite3_column_text(stmt, 0)),
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
