import SwiftUI

struct StatsView: View {
    @State private var stats: [SongStat] = []
    @State private var listening: [ListeningStat] = []
    @State private var totals: (today: Double, week: Double, allTime: Double) = (0, 0, 0)
    @State private var byDay: [(day: String, seconds: Double)] = []

    var body: some View {
        let totalPlays = stats.reduce(0) { $0 + $1.plays }
        let totalSkips = stats.reduce(0) { $0 + $1.skips }
        let totalCompleted = stats.reduce(0) { $0 + $1.completions }
        // ponytail: Dictionary for O(1) per-song lookup in the Songs section
        let timeByPath = Dictionary(uniqueKeysWithValues: listening.map { ($0.songPath, $0.seconds) })

        List {
            Section("Overview") {
                LabeledContent("Total plays", value: "\(totalPlays)")
                LabeledContent("Completed",   value: "\(totalCompleted)")
                LabeledContent("Skipped",     value: "\(totalSkips)")
            }

            Section("Time listened") {
                LabeledContent("Today",       value: formatSeconds(totals.today))
                LabeledContent("Last 7 days", value: formatSeconds(totals.week))
                LabeledContent("All time",    value: formatSeconds(totals.allTime))
            }

            if !byDay.isEmpty {
                Section("Daily history") {
                    ForEach(byDay, id: \.day) { row in
                        LabeledContent(row.day, value: formatSeconds(row.seconds))
                    }
                }
            }

            Section("Songs") {
                ForEach(stats, id: \.songPath) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).lineLimit(1)
                        let listened = timeByPath[s.songPath].map { " · " + formatSeconds($0) } ?? ""
                        Text("\(s.plays) play\(s.plays == 1 ? "" : "s") · \(s.completions) completed · \(s.skips) skipped\(listened)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .task {
            stats    = AnalyticsService.songStats()
            listening = AnalyticsService.listeningBySong()
            totals   = AnalyticsService.listeningTotals()
            byDay    = AnalyticsService.listeningByDay()
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let t = Int(s)
        let h = t / 3600
        let m = (t % 3600) / 60
        if t < 60 { return "\(t)s" }
        if h > 0  { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
