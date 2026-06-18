//
//  EchoApp.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var navigationState = AppNavigationState()
    @StateObject var libraryViewModel = MusicLibraryViewModel()
    @StateObject var playerViewModel = AudioPlayerViewModel()

    var body: some Scene {
        WindowGroup {
            Root()
                .environmentObject(navigationState)
                .environmentObject(libraryViewModel)
                .environmentObject(playerViewModel)
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

