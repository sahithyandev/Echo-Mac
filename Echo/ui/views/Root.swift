import Foundation
import SwiftUI

struct Root: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var libraryViewModel: MusicLibraryViewModel
    @EnvironmentObject private var playerViewModel: AudioPlayerViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationState.currentPage) {
                Label("Home", systemImage: "music.note.house")
                    .tag(Page.home)

                if playerViewModel.nowPlaying != nil {
                    Label("Now Playing", systemImage: "music.note")
                        .tag(Page.nowPlaying)
                }

                Label("Stats", systemImage: "chart.bar")
                    .tag(Page.stats)

                Label("Settings", systemImage: "gear")
                    .tag(Page.settings)
            }
        } detail: {
            switch navigationState.currentPage {
            case .nowPlaying:
                NowPlayingView(playerViewModel: playerViewModel)
            case .stats:
                StatsView()
            case .settings:
                Settings()
            default:
                Home(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            }
        }
        // Wire our #FF3366 accent through the whole view hierarchy:
        // sidebar selection tint, button defaults, progress fills.
        .tint(AppColor.accent)
        .safeAreaInset(edge: .bottom) {
            if playerViewModel.nowPlaying != nil && navigationState.currentPage != .nowPlaying {
                PlayerControlsView(playerViewModel: playerViewModel) {
                    navigationState.currentPage = .nowPlaying
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Removed: the forced auto-navigation to Now Playing on every play.
        // The mini-player is the bridge — users stay where they are and
        // tap it to expand into the full Now Playing screen.
    }
}
