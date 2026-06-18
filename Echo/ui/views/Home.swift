import SwiftUI

struct Home: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @AppStorage("libraryDirectory") var libraryDirectory: String = "/Users/\(NSUserName())/Music"

    var body: some View {
        ZStack(alignment: .bottom) {
            List(libraryViewModel.songs) { song in
                HStack(spacing: 10) {
                    SongArtworkView(song: song, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let detail = subtitle(for: song) {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
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

            if playerViewModel.nowPlaying != nil {
                PlayerControlsView(playerViewModel: playerViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func subtitle(for song: Song) -> String? {
        switch (song.artist, song.album) {
        case (let artist?, let album?): return "\(artist) — \(album)"
        case (let artist?, nil):        return artist
        case (nil, let album?):         return album
        case (nil, nil):                return nil
        }
    }
}
