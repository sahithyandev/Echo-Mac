import SwiftUI
import Charts

// The signature visual motif of Echo: a mini bar chart of listening history.
// Swift Charts auto-scales each sparkline to its own data range,
// so each song's listening pattern is visible relative to itself.
struct Sparkline: View {
    let values: [Double]
    var color: Color = AppColor.tealLight
    var cornerRadius: CGFloat = 2

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                BarMark(
                    x: .value("Day", i),
                    y: .value("Listening", v)
                )
                .cornerRadius(cornerRadius)
                .foregroundStyle(color.gradient)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
