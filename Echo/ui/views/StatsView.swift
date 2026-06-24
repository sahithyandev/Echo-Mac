import SwiftUI
import Charts

struct StatsView: View {
    @State private var listening: [ListeningStat] = []
    @State private var totals: (today: Double, week: Double, allTime: Double) = (0, 0, 0)
    @State private var byDay: [DayPoint] = []

    struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let hours: Double
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                heroSection
                if !byDay.isEmpty    { dailyChart }
                if !qualifiedSongs.isEmpty { topSongsSection }
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle("Stats")
        .task {
            listening = AnalyticsService.listeningBySong()
            totals    = AnalyticsService.listeningTotals()
            byDay     = makeDayPoints(AnalyticsService.listeningByDay().reversed())
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

    private var qualifiedSongs: [ListeningStat] {
        listening.filter { $0.seconds >= 1800 }
    }

    // MARK: - Top songs

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            eyebrow("Top songs")

            VStack(spacing: 0) {
                ForEach(Array(qualifiedSongs.prefix(10).enumerated()), id: \.element.songPath) { i, stat in
                    HStack(spacing: AppSpacing.md) {
                        Text("\(i + 1)")
                            .font(.system(size: 11, design: .rounded).weight(.bold))
                            .foregroundStyle(.quaternary)
                            .frame(width: 18, alignment: .trailing)

                        Text(stat.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(formatSeconds(stat.seconds))
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppColor.accent)
                    }
                    .padding(.vertical, AppSpacing.sm)

                    if i < min(9, qualifiedSongs.count - 1) {
                        Divider().opacity(0.07)
                    }
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
