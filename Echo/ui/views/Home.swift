import SwiftUI

struct Home: View {
    @StateObject private var libraryViewModel = MusicLibraryViewModel()
    @StateObject private var playerViewModel = AudioPlayerViewModel()

    var username = NSUserName()

    var body: some View {
        ZStack(alignment: .bottom) {
            List(libraryViewModel.songs) { song in
                HStack(spacing: 10) {
                    SongArtworkView(song: song, size: 36)
                    Text(song.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .onTapGesture {
                    withAnimation(.spring()) {
                        playerViewModel.play(song)
                    }
                }
            }
            .onAppear {
                libraryViewModel.load(from: URL(fileURLWithPath: "/Users/\(username)/Music"))
            }

            if playerViewModel.nowPlaying != nil {
                PlayerControlsView(playerViewModel: playerViewModel)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

#Preview {
    Home()
}
