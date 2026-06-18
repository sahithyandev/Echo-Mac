import SwiftUI

struct Home: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @AppStorage("libraryDirectory") var libraryDirectory: String = "/Users/\(NSUserName())/Music"

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
                        playerViewModel.play(song, in: libraryViewModel.songs)
                    }
                }
            }
            .onAppear {
                libraryViewModel.load(from: URL(fileURLWithPath: libraryDirectory))
            }

        }
    }
}

