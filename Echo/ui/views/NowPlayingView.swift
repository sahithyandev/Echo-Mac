import SwiftUI
import EchoCore

struct NowPlayingView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    private var displayedProgress: Double {
        isScrubbing ? scrubProgress : playerViewModel.progress
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                artwork
                songInfo
                scrubber
                playbackControls
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
        }
        .frame(minWidth: 400)
    }

    private var artwork: some View {
        Group {
            if let song = playerViewModel.nowPlaying {
                SongArtworkView(song: song, size: 220)
                    .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
            }
        }
    }

    private var songInfo: some View {
        VStack(spacing: 5) {
            Text(playerViewModel.nowPlaying?.title ?? "")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let song = playerViewModel.nowPlaying, let detail = subtitle(for: song) {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let fillWidth = (trackWidth * displayedProgress).clamped(to: 0...trackWidth)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: max(fillWidth, 0), height: 4)
                        .animation(isScrubbing ? nil : .linear(duration: 0.5), value: displayedProgress)

                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .offset(x: fillWidth - 7)
                        .scaleEffect(isScrubbing ? 1.2 : 1)
                        .animation(.easeInOut(duration: 0.15), value: isScrubbing)
                }
                .frame(height: 14)
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
            .frame(height: 14)

            HStack {
                Text(formatTime(isScrubbing
                    ? playerViewModel.duration * scrubProgress
                    : playerViewModel.duration - playerViewModel.timeRemaining))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("-" + formatTime(isScrubbing
                    ? playerViewModel.duration * (1 - scrubProgress)
                    : playerViewModel.timeRemaining))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 44) {
            Button { playerViewModel.playPrev() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(playerViewModel.canPlayPrev
                        ? AnyShapeStyle(.primary)
                        : AnyShapeStyle(.primary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(!playerViewModel.canPlayPrev)

            Button { playerViewModel.togglePlayPause() } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(AppColor.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button { playerViewModel.playNext() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(playerViewModel.canPlayNext
                        ? AnyShapeStyle(.primary)
                        : AnyShapeStyle(.primary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .disabled(!playerViewModel.canPlayNext)
        }
    }

    private func subtitle(for song: Song) -> String? {
        switch (song.artist, song.album) {
        case (let a?, let b?): return "\(a) — \(b)"
        case (let a?, nil):    return a
        case (nil, let b?):    return b
        case (nil, nil):       return nil
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
