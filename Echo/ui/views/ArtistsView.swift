import SwiftUI

struct ArtistsView: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @EnvironmentObject private var navigationState: AppNavigationState

    private struct Artist: Identifiable {
        let name: String
        let songCount: Int
        let cover: Song
        var id: String { name }
    }

    private var artists: [Artist] {
        let pairs = libraryViewModel.songs.flatMap { song in
            libraryViewModel.artistNames(for: song).map { ($0, song) }
        }
        return Dictionary(grouping: pairs) { $0.0 }
            .map { name, rows in Artist(name: name, songCount: rows.count, cover: rows[0].1) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geo in
            let isCompact = gridColumnCount(width: geo.size.width, minItemWidth: 140, spacing: AppSpacing.lg) <= 3
            ScrollView {
                if artists.isEmpty {
                    ContentUnavailableView("No artists", systemImage: "music.mic", description: Text("Songs with artist metadata will show up here."))
                        .padding(.top, AppSpacing.xl)
                } else {
                    let columns = isCompact
                        ? [GridItem(.flexible())]
                        : [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.lg)]
                    LazyVGrid(columns: columns, spacing: AppSpacing.lg) {
                        ForEach(artists) { artist in
                            ArtistCell(artist: artist, isCompact: isCompact) { navigate(to: artist.name) }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .animation(.easeInOut(duration: 0.25), value: isCompact)
                }
            }
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("Artists")
    }

    private func navigate(to artist: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            navigationState.currentPage = .artist(artist)
        }
    }

    private struct ArtistCell: View {
        let artist: Artist
        let isCompact: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                let layout = isCompact ? AnyLayout(HStackLayout(spacing: AppSpacing.sm)) : AnyLayout(VStackLayout(spacing: AppSpacing.xs))
                layout {
                    SongArtworkView(song: artist.cover, size: isCompact ? 44 : 152)
                        .clipShape(Circle())
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if isCompact {
                        Spacer()
                        Text("\(artist.songCount)")
                            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(artist.songCount) song\(artist.songCount == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, isCompact ? AppSpacing.xs : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
