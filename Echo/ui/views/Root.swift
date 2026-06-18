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
        ZStack {
            NavigationSplitView {
                List(selection: $navigationState.currentPage) {
                    Label("Home", systemImage: "music.note.house")
                        .tag(Page.home)
                    Label("Settings", systemImage: "gear")
                        .tag(Page.settings)
                }
            } detail: {
                switch navigationState.currentPage {
                case .settings:
                    Settings()
                default:
                    Home(libraryViewModel: libraryViewModel, playerViewModel: playerViewModel)
                }
            }

            .safeAreaInset(edge: .bottom) {
                if playerViewModel.nowPlaying != nil {
                    PlayerControlsView(playerViewModel: playerViewModel)
                        .transition(.move(edge: .bottom))
                }
            }
        }
    }

}

#Preview {
    Root()
}
