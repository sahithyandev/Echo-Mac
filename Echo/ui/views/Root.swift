import Foundation
import SwiftUI

struct Root: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var libraryViewModel: MusicLibraryViewModel
    @EnvironmentObject private var playerViewModel: AudioPlayerViewModel
    @Namespace private var heroNamespace

    private var animatedPageBinding: Binding<Page?> {
        Binding(
            get: { navigationState.currentPage },
            set: { if let p = $0 { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { navigationState.currentPage = p } } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: animatedPageBinding) {
                Label("Home", systemImage: "music.note.house")
                    .tag(Page.home)

                if playerViewModel.nowPlaying != nil {
                    Label("Now Playing", systemImage: "music.note")
                        .tag(Page.nowPlaying)
                }

                Label("Stats", systemImage: "chart.bar")
                    .tag(Page.stats)

                Label("Albums", systemImage: "square.stack")
                    .tag(Page.albums)

                Label("Artists", systemImage: "music.mic")
                    .tag(Page.artists)

                Label("Settings", systemImage: "gear")
                    .tag(Page.settings)
            }
        } detail: {
            switch navigationState.currentPage {
            case .nowPlaying:
                NowPlayingView(playerViewModel: playerViewModel, namespace: heroNamespace)
            case .stats:
                StatsView()
            case .settings:
                Settings()
            case .albums:
                AlbumsView(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            case .artists:
                ArtistsView(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            case .album(let name):
                AlbumDetailView(album: name, libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            case .artist(let name):
                ArtistDetailView(artist: name, libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            default:
                Home(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            }
        }
        // Wire our #FF3366 accent through the whole view hierarchy:
        // sidebar selection tint, button defaults, progress fills.
        .tint(AppColor.accent)
        .safeAreaInset(edge: .bottom) {
            if playerViewModel.nowPlaying != nil && navigationState.currentPage != .nowPlaying {
                PlayerControlsView(playerViewModel: playerViewModel, namespace: heroNamespace) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        navigationState.currentPage = .nowPlaying
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Removed: the forced auto-navigation to Now Playing on every play.
        // The mini-player is the bridge — users stay where they are and
        // tap it to expand into the full Now Playing screen.
    }
}
