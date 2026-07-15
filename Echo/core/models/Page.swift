//
//  Page.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-17.
//

import Foundation

enum Page: Hashable {
    case home
    case nowPlaying
    case stats
    case settings
    case albums
    case artists
    case album(String)   // album name
    case artist(String)  // artist name
}

