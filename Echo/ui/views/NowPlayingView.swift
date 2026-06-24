import SwiftUI
import EchoCore

struct NowPlayingView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                artwork
                songInfo
                Scrubber(
                    progress: playerViewModel.progress,
                    duration: playerViewModel.duration,
                    onSeek: { playerViewModel.seek(to: $0) }
                )
                playbackControls
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xl)
        }
        .frame(minWidth: 400)
    }

    // MARK: - Subviews

    private var artwork: some View {
        Group {
            if let song = playerViewModel.nowPlaying {
                SongArtworkView(song: song, size: 220)
                    .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
            }
        }
    }

    private var songInfo: some View {
        VStack(spacing: 5) {
            Text(playerViewModel.nowPlaying?.title ?? "")
                .font(.appTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let song = playerViewModel.nowPlaying, let sub = subtitle(for: song) {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 36) {
            Button { playerViewModel.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(playerViewModel.isShuffled
                        ? AnyShapeStyle(AppColor.accent)
                        : AnyShapeStyle(.primary.opacity(0.3)))
            }
            .buttonStyle(.plain)

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
                    .frame(width: 64, height: 64)
                    .background(AppColor.accent)
                    .clipShape(Circle())
                    .shadow(color: AppColor.accent.opacity(0.4), radius: 12, x: 0, y: 4)
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

}
