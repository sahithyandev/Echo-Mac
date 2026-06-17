import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var displayedProgress: Double {
        isScrubbing ? scrubProgress : playerViewModel.progress
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let song = playerViewModel.nowPlaying {
                    SongArtworkView(song: song, size: 40)
                }

                Text(playerViewModel.nowPlaying?.title ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.cream)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        playerViewModel.playPrev()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playerViewModel.canPlayPrev ? AppColor.cream : AppColor.cream.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerViewModel.canPlayPrev)

                    Button {
                        playerViewModel.togglePlayPause()
                    } label: {
                        Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.navy)
                            .frame(width: 36, height: 36)
                            .background(AppColor.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        playerViewModel.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playerViewModel.canPlayNext ? AppColor.cream : AppColor.cream.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerViewModel.canPlayNext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GeometryReader { geo in
                let trackWidth = geo.size.width
                let fillWidth = trackWidth * displayedProgress
                let thumbX = fillWidth.clamped(to: 0...trackWidth)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.cream.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: max(fillWidth, 0), height: 3)
                        .animation(isScrubbing ? nil : .linear(duration: 0.5), value: displayedProgress)

                    Circle()
                        .fill(AppColor.cream)
                        .frame(width: 10, height: 10)
                        .offset(x: thumbX - 5)
                        .opacity(isScrubbing ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: isScrubbing)
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubProgress = (value.location.x / trackWidth).clamped(to: 0...1)
                            isScrubbing = true
                        }
                        .onEnded { value in
                            let fraction = (value.location.x / trackWidth).clamped(to: 0...1)
                            playerViewModel.seek(to: fraction * playerViewModel.duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            HStack {
                Spacer()
                Text("-" + Self.formatTime(isScrubbing
                    ? playerViewModel.duration * (1 - scrubProgress)
                    : playerViewModel.timeRemaining))
                    .font(.system(size: 10, weight: .regular).monospacedDigit())
                    .foregroundStyle(AppColor.cream.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(AppColor.navy)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
