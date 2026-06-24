import SwiftUI
import Charts

struct StatsView: View {
    @State private var totals: (today: Double, week: Double, allTime: Double) = (0, 0, 0)
    @State private var byDay: [DayPoint] = []
    @State private var topArtists: [(name: String, seconds: Double)] = []
    @State private var topAlbums:  [(name: String, seconds: Double)] = []
    @State private var topYears:   [(name: String, seconds: Double)] = []
    @State private var topGenres:  [(name: String, seconds: Double)] = []

    struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let hours: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                heroSection
                if !byDay.isEmpty      { dailyChart }
                if !topArtists.isEmpty { rankedList(title: "Artists", rows: topArtists) }
                if !topAlbums.isEmpty  { rankedList(title: "Albums",  rows: topAlbums) }
                if !topYears.isEmpty   { rankedList(title: "Years",   rows: topYears) }
                if !topGenres.isEmpty  { rankedList(title: "Genres",  rows: topGenres) }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("Stats")
        .task {
            totals    = PlaybackStore.listeningTotals()
            byDay     = makeDayPoints(PlaybackStore.listeningByDay().reversed())
            topArtists = PlaybackStore.topByArtist()
            topAlbums  = PlaybackStore.topByAlbum()
            topYears   = PlaybackStore.topByYear()
            topGenres  = PlaybackStore.topByGenre()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow("All time")
                Text(formatSeconds(totals.allTime))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(AppColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            HStack(spacing: AppSpacing.xl) {
                miniStat(label: "Today",     value: formatSeconds(totals.today))
                miniStat(label: "This week", value: formatSeconds(totals.week))
            }
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            eyebrow(label)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            eyebrow("Last 30 days")

            Chart(byDay) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Hours", point.hours)
                )
                .cornerRadius(3)
                .foregroundStyle(AppColor.accent.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel(format: .dateTime.month().day())
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel {
                        if let h = value.as(Double.self) {
                            Text(h == 0 ? "" : String(format: "%.1fh", h))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    // MARK: - Ranked list

    private func rankedList(title: String, rows: some Collection<(name: String, seconds: Double)>) -> some View {
        let items = Array(rows)
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            eyebrow(title)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: AppSpacing.md) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, design: .rounded).weight(.bold))
                            .foregroundStyle(.quaternary)
                            .frame(width: 18, alignment: .trailing)
                        Text(row.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(formatSeconds(row.seconds))
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppColor.accent)
                    }
                    .padding(.vertical, AppSpacing.sm)
                    if i < items.count - 1 { Divider().opacity(0.07) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .kerning(1.2)
    }

    private func makeDayPoints(_ rows: [(day: String, seconds: Double)]) -> [DayPoint] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return rows.compactMap { row in
            fmt.date(from: row.day).map { DayPoint(date: $0, hours: row.seconds / 3600) }
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60
        if t < 60 { return "\(t)s" }
        if h > 0  { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
