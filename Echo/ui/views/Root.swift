//
//  Root.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-18.
//

import Foundation
import SwiftUI

struct Root : View {
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var libraryViewModel: MusicLibraryViewModel
    @EnvironmentObject private var playerViewModel: AudioPlayerViewModel

    var body : some View {
        NavigationSplitView {
            List(selection: $navigationState.currentPage) {
                Label("Home", systemImage: "music.note.house")
                    .tag(Page.home)

                if playerViewModel.nowPlaying != nil {
                    Label("Now Playing", systemImage: "music.note")
                        .tag(Page.nowPlaying)
                }

                Label("Settings", systemImage: "gear")
                    .tag(Page.settings)
            }
        } detail: {
            switch navigationState.currentPage {
            case .nowPlaying:
                NowPlayingView(playerViewModel: playerViewModel)
            case .settings:
                Settings()
            default:
                Home(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if playerViewModel.nowPlaying != nil && navigationState.currentPage != .nowPlaying {
                PlayerControlsView(playerViewModel: playerViewModel) {
                    navigationState.currentPage = .nowPlaying
                }
                .transition(.move(edge: .bottom))
            }
        }
        .onChange(of: playerViewModel.nowPlaying) { _, song in
            if song != nil {
                navigationState.currentPage = .nowPlaying
            } else {
                navigationState.currentPage = .home
            }
        }
    }

}

#Preview {
    Root()
}
