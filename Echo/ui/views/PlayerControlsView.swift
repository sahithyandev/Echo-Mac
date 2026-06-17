import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playerViewModel.nowPlaying?.title ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.surface)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button {
                playerViewModel.togglePlayPause()
            } label: {
                Image(systemName: playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.background)
                    .frame(width: 36, height: 36)
                    .background(Color.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
