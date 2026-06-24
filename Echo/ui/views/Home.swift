import SwiftUI
import EchoCore

struct Home: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @AppStorage("libraryDirectory") var libraryDirectory: String = "/Users/\(NSUserName())/Music"

    @State private var searchText = ""

    private var filtered: [Song] {
        guard !searchText.isEmpty else { return libraryViewModel.songs }
        let q = searchText
        return libraryViewModel.songs.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist?.localizedCaseInsensitiveContains(q) == true)
            || ($0.album?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !playerViewModel.recommendations.isEmpty && searchText.isEmpty {
                RecommendedSongsStrip(songs: playerViewModel.recommendations) { song in
                    playerViewModel.play(song, in: playerViewModel.queue)
                }
                Divider()
            }
            songContent
        }
        .background(AppColor.background.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search songs, artists, albums")
        .onChange(of: libraryViewModel.songs) { _, songs in
            playerViewModel.updateLibrary(songs)
        }
        .onAppear {
            libraryViewModel.load(from: URL(fileURLWithPath: libraryDirectory))
            playerViewModel.loadInitialRecommendations(from: libraryViewModel.songs)
        }
    }

    // MARK: - Song List

    @ViewBuilder
    private var songContent: some View {
        if let error = libraryViewModel.errorMessage {
            ContentUnavailableView(
                "Couldn't load library",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if libraryViewModel.songs.isEmpty {
            ContentUnavailableView(
                "No songs",
                systemImage: "music.note",
                description: Text("Add MP3 files to your Music folder or choose another folder in Settings.")
            )
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(filtered) { song in
                SongRow(song: song)
                .onTapGesture {
                    withAnimation(.spring()) {
                        playerViewModel.play(song, in: filtered)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

}
