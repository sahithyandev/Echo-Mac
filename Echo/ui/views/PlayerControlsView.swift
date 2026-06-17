import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    var body: some View {
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
        .background(AppColor.navy)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
