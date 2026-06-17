//
//  Home.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import SwiftUI

struct Home: View {
    @StateObject private var viewModel = FileListViewModel()
    @StateObject private var playerModel = AudioPlayerViewModel()
    
    var username = NSUserName()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            List(viewModel.files, id: \.self) { url in
                Text(url.lastPathComponent)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            playerModel.play(url)
                        }
                    }
            }
            .onAppear {
                viewModel.loadFiles(at: URL(fileURLWithPath: "/Users/\(username)/Music"))
            }
            
            if playerModel.nowPlaying != nil {
                PlayerControlsView(playerModel: playerModel)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

#Preview {
    Home()
}
