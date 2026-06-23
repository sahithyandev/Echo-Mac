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

// ponytail: raw SQLite3 (built into OS), no GRDB/SQLite.swift dep needed
enum AnalyticsService {
    private static let queue = DispatchQueue(label: "echo.analytics", qos: .background)
    private static let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
