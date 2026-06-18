//
//  EchoApp.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import SwiftUI

@main
struct EchoApp: App {
    @StateObject var navigationState = AppNavigationState()

    var body: some Scene {
        WindowGroup {
            Root().environmentObject(navigationState)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    navigationState.currentPage = .settings
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

