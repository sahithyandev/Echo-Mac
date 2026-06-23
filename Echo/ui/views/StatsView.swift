import SwiftUI

struct StatsView: View {
    @State private var stats: [SongStat] = []

    var body: some View {
        let totalPlays = stats.reduce(0) { $0 + $1.plays }
        let totalSkips = stats.reduce(0) { $0 + $1.skips }
        let totalCompleted = stats.reduce(0) { $0 + $1.completions }

        List {
            Section("Overview") {
                LabeledContent("Total plays", value: "\(totalPlays)")
                LabeledContent("Completed",   value: "\(totalCompleted)")
                LabeledContent("Skipped",     value: "\(totalSkips)")
            }

            Section("Songs") {
                ForEach(stats, id: \.songPath) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).lineLimit(1)
                        Text("\(s.plays) play\(s.plays == 1 ? "" : "s") · \(s.completions) completed · \(s.skips) skipped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .task { stats = AnalyticsService.songStats() }
    }
}
