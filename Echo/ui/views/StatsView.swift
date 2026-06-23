import SwiftUI

struct StatsView: View {
    @State private var events: [AnalyticsEvent] = []

    private struct SongStats {
        let title: String
        var plays: Int = 0
        var skips: Int = 0
        var completions: Int = 0
    }

    private var songStats: [SongStats] {
        var map: [String: SongStats] = [:]
        for e in events {
            var s = map[e.songPath, default: SongStats(title: e.title)]
            switch e.event {
            case "play":       s.plays += 1
            case "skip":       s.skips += 1
            case "complete":   s.completions += 1
            default: break
            }
            map[e.songPath] = s
        }
        return map.values.sorted { $0.plays > $1.plays }
    }

    var body: some View {
        let stats = songStats
        let totalPlays = stats.reduce(0) { $0 + $1.plays }
        let totalSkips = stats.reduce(0) { $0 + $1.skips }
        let totalCompleted = stats.reduce(0) { $0 + $1.completions }

        List {
            Section("Overview") {
                LabeledContent("Total plays", value: "\(totalPlays)")
                LabeledContent("Completed", value: "\(totalCompleted)")
                LabeledContent("Skipped", value: "\(totalSkips)")
            }

            Section("Songs") {
                ForEach(stats, id: \.title) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).lineLimit(1)
                            Text("\(s.plays) play\(s.plays == 1 ? "" : "s") · \(s.completions) completed · \(s.skips) skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .task { events = AnalyticsService.loadAll() }
    }
}
