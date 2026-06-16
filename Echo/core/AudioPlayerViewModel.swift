//
//  AudioPlayerViewModel.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AudioPlayerViewModel : ObservableObject {
    @Published var nowPlaying: URL?
    
    private var player: AVAudioPlayer?
    
    func play(_ file: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: file)
            player?.play()
            nowPlaying = file
        } catch {
            print("Error occurred")
        }
    }
    
    func pause() {
        guard let player = player else {
            return
        }
        player.pause()
    }
}
