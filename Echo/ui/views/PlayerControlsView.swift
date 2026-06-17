import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    var body: some View {
        HStack {
            Text(playerViewModel.nowPlaying?.title ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Pause") {
                playerViewModel.pause()
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
