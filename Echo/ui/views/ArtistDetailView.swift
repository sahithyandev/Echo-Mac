import SwiftUI

struct ArtistDetailView: View {
    let artist: String
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @EnvironmentObject private var navigationState: AppNavigationState

    private var tracks: [Song] { libraryViewModel.songs(byArtist: artist) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header
                VStack(spacing: 0) {
                    ForEach(tracks) { song in
                        SongRow(song: song)
                            .onTapGesture {
                                withAnimation(.spring()) {
                                    playerViewModel.play(song, in: tracks)
                                }
                            }
                            .padding(.vertical, AppSpacing.xs)
                        if song.id != tracks.last?.id { Divider().opacity(0.07) }
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle(artist)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        navigationState.currentPage = .artists
                    }
                } label: {
                    Label("Artists", systemImage: "chevron.left")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.lg) {
            if let cover = tracks.first {
                SongArtworkView(song: cover, size: 120)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(artist)
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("\(tracks.count) song\(tracks.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if let first = tracks.first {
                    Button {
                        withAnimation(.spring()) {
                            playerViewModel.play(first, in: tracks)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accent)
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
    }
}
