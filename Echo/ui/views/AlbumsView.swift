import SwiftUI

struct AlbumsView: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @EnvironmentObject private var navigationState: AppNavigationState

    private struct Album: Identifiable {
        let name: String
        let artist: String?
        let cover: Song
        var id: String { name }
    }

    private var albums: [Album] {
        Dictionary(grouping: libraryViewModel.songs) { $0.album ?? "Unknown Album" }
            .map { name, songs in Album(name: name, artist: songs.first?.artist, cover: songs[0]) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geo in
            let isCompact = gridColumnCount(width: geo.size.width, minItemWidth: 140, spacing: AppSpacing.lg) <= 3
            ScrollView {
                if albums.isEmpty {
                    ContentUnavailableView("No albums", systemImage: "square.stack", description: Text("Songs with album metadata will show up here."))
                        .padding(.top, AppSpacing.xl)
                } else {
                    let columns = isCompact
                        ? [GridItem(.flexible())]
                        : [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.lg)]
                    LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
                        ForEach(albums) { album in
                            AlbumCell(album: album, isCompact: isCompact) { navigate(to: album.name) }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .animation(.easeInOut(duration: 0.25), value: isCompact)
                }
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Albums")
    }

    private func navigate(to album: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            navigationState.currentPage = .album(album)
        }
    }

    private struct AlbumCell: View {
        let album: Album
        let isCompact: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                let layout = isCompact ? AnyLayout(HStackLayout(spacing: AppSpacing.sm)) : AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xs))
                layout {
                    SongArtworkView(song: album.cover, size: isCompact ? 44 : 152)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if let artist = album.artist {
                            Text(artist)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isCompact { Spacer(minLength: AppSpacing.sm) }
                }
                .padding(.vertical, isCompact ? AppSpacing.xs : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
