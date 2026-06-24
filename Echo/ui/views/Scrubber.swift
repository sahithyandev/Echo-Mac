import SwiftUI

// Shared scrubber used by NowPlayingView and PlayerControlsView.
// Replaces two near-identical GeometryReader implementations.
struct Scrubber: View {
    let progress: Double
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    var trackHeight: CGFloat = 4
    var showTimeLabels: Bool = true
    // When false, thumb only appears while actively scrubbing (mini-player style)
    var alwaysShowThumb: Bool = true

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var displayed: Double { isScrubbing ? scrubProgress : progress }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let fill = (w * displayed).clamped(to: 0...w)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.12))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: max(fill, 0), height: trackHeight)
                        .animation(isScrubbing ? nil : .linear(duration: 0.5), value: displayed)
                    Circle()
                        .fill(.white)
                        .frame(width: trackHeight * 3.5, height: trackHeight * 3.5)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: fill - trackHeight * 1.75)
                        .opacity((alwaysShowThumb || isScrubbing) ? 1 : 0)
                        .scaleEffect(isScrubbing ? 1.2 : 1)
                        .animation(.easeInOut(duration: 0.15), value: isScrubbing)
                }
                .frame(height: trackHeight * 3.5)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            scrubProgress = (v.location.x / w).clamped(to: 0...1)
                            isScrubbing = true
                        }
                        .onEnded { v in
                            onSeek((v.location.x / w).clamped(to: 0...1) * duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: trackHeight * 3.5)

            if showTimeLabels {
                HStack {
                    Text(formatTime(duration * displayed))
                        .font(.appTime)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("-" + formatTime(duration * (1 - displayed)))
                        .font(.appTime)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
