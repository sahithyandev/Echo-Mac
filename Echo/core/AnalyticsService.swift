import Foundation
import EchoCore

enum AnalyticsService {
    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Echo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analytics.jsonl")
    }()

    private struct Event: Encodable {
        let event: String
        let songPath: String
        let title: String
        let progress: Double
        let timestamp: Double
    }

    static func track(event: String, song: Song, progress: Double) {
        let e = Event(
            event: event,
            songPath: song.url.lastPathComponent,
            title: song.title,
            progress: round(progress * 1000) / 1000,
            timestamp: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(e),
              let line = String(data: data, encoding: .utf8) else { return }
        let toWrite = line + "\n"
        DispatchQueue.global(qos: .background).async {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(toWrite.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? toWrite.write(to: fileURL, atomically: false, encoding: .utf8)
            }
        }
    }
}
