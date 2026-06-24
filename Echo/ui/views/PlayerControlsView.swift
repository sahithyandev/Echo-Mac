import SwiftUI
import EchoCore

struct PlayerControlsView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    var onInfoTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.md) {
                // Song info — tapping opens Now Playing
                Button { onInfoTap() } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if let song = playerViewModel.nowPlaying {
                            SongArtworkView(song: song, size: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playerViewModel.nowPlaying?.title ?? "")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let detail = playerViewModel.nowPlaying.flatMap(subtitle) {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Transport controls
                HStack(spacing: AppSpacing.sm) {
                    Button { playerViewModel.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playerViewModel.isShuffled
                                ? AnyShapeStyle(AppColor.accent)
                                : AnyShapeStyle(.primary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)

                    Button { playerViewModel.playPrev() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playerViewModel.canPlayPrev
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(.primary.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerViewModel.canPlayPrev)

                    Button { playerViewModel.togglePlayPause() } label: {
                        Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppColor.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button { playerViewModel.playNext() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playerViewModel.canPlayNext
                                ? AnyShapeStyle(.primary)
                                : AnyShapeStyle(.primary.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerViewModel.canPlayNext)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)

            // Mini scrubber: thumb hidden until dragged, no time labels (compact)
            Scrubber(
                progress: playerViewModel.progress,
                duration: playerViewModel.duration,
                onSeek: { playerViewModel.seek(to: $0) },
                trackHeight: 3,
                showTimeLabels: false,
                alwaysShowThumb: false
            )
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .shadow(color: .black.opacity(0.15), radius: AppRadius.lg, x: 0, y: 4)
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
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
