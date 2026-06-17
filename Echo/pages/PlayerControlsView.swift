//
//  PlayerControlsView.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-17.
//

import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var playerModel: AudioPlayerViewModel

    var body: some View {
        HStack {
            Text(playerModel.nowPlaying?.lastPathComponent ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Pause") {
                playerModel.pause()
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}
