import SwiftUI

struct Home: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel

    @State private var searchText = ""
    @State private var selectedLibraryId: String?

    private var filtered: [Song] {
        var result = libraryViewModel.songs
        if let selectedLibraryId {
            result = result.filter { $0.libraryId == selectedLibraryId }
        }
        guard !searchText.isEmpty else { return result }
        let q = searchText
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.artist?.localizedCaseInsensitiveContains(q) == true)
            || ($0.album?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !playerViewModel.recommendations.isEmpty && searchText.isEmpty {
                RecommendedSongsStrip(songs: playerViewModel.recommendations) { song in
                    playerViewModel.playFromUpNext(song)
                }
                Divider()
            }
            songContent
        }
        .background(AppColor.background.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "Search songs, artists, albums")
        .toolbar {
            // Docked in the same toolbar as the search field (added via .searchable above)
            // so the two sit next to each other.
            if libraryViewModel.libraries.count > 1 {
                ToolbarItem(placement: .automatic) { libraryPicker }
            }
        }
        .onChange(of: libraryViewModel.songs) { _, songs in
            playerViewModel.updateLibrary(songs)
        }
        .onChange(of: selectedLibraryId) { _, libraryId in
            playerViewModel.loadInitialRecommendations(from: libraryViewModel.songs, libraryId: libraryId)
        }
        .onAppear {
            libraryViewModel.reload()
            playerViewModel.loadInitialRecommendations(from: libraryViewModel.songs, libraryId: selectedLibraryId)
        }
    }

    private var libraryPicker: some View {
        Picker("Library", selection: $selectedLibraryId) {
            Text("All Libraries").tag(String?.none)
            ForEach(libraryViewModel.libraries) { library in
                Text(library.name).tag(String?.some(library.id))
            }
        }
        .pickerStyle(.menu)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraryViewModel.songs.isEmpty {
            ContentUnavailableView(
                "No songs",
                systemImage: "music.note",
                description: Text("Add MP3 files to your Music folder or choose another folder in Settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
