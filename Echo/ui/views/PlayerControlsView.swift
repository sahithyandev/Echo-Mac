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
