import SwiftUI
import EchoCore

struct Home: View {
    @ObservedObject var libraryViewModel: MusicLibraryViewModel
    @ObservedObject var playerViewModel: AudioPlayerViewModel
    @AppStorage("libraryDirectory") var libraryDirectory: String = "/Users/\(NSUserName())/Music"
    #if DEBUG
    @State private var showingDebugSheet = false
    #endif

    var body: some View {
        ZStack(alignment: .bottom) {
            List(libraryViewModel.songs) { song in
                HStack(spacing: 10) {
                    SongArtworkView(song: song, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let detail = subtitle(for: song) {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring()) {
                        playerViewModel.play(song, in: libraryViewModel.songs)
                    }
                }
            }
            .onAppear {
                libraryViewModel.load(from: URL(fileURLWithPath: libraryDirectory))
            }

            if playerViewModel.nowPlaying != nil {
                PlayerControlsView(playerViewModel: playerViewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingDebugSheet = true
                } label: {
                    Label(analysisLabel, systemImage: "waveform.badge.magnifyingglass")
                        .symbolEffect(.pulse, isActive: {
                            if case .analyzing = libraryViewModel.debugAnalysisState { return true }
                            return false
                        }())
                }
            }
        }
        .sheet(isPresented: $showingDebugSheet) {
            DebugAnalysisSheet(state: libraryViewModel.debugAnalysisState)
        }
        #endif
    }

    #if DEBUG
    private var analysisLabel: String {
        switch libraryViewModel.debugAnalysisState {
        case .idle:         return "Analysis"
        case .analyzing:    return "Analyzing…"
        case .done(let f):  return "\(f.count) analyzed"
        }
    }
    #endif

    private func subtitle(for song: Song) -> String? {
        switch (song.artist, song.album) {
        case (let artist?, let album?): return "\(artist) — \(album)"
        case (let artist?, nil):        return artist
        case (nil, let album?):         return album
        case (nil, nil):                return nil
        }
    }
}

#if DEBUG
private struct DebugAnalysisSheet: View {
    let state: MusicLibraryViewModel.DebugAnalysisState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Feature Analysis")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            .padding()

            Divider()

            switch state {
            case .idle:
                ContentUnavailableView("Not started", systemImage: "clock",
                    description: Text("Analysis begins when the library loads."))
            case .analyzing:
                ContentUnavailableView("Analyzing…", systemImage: "waveform",
                    description: Text("Extracting features from your library."))
            case .done(let features):
                Table(features.sorted { $0.songURL.lastPathComponent < $1.songURL.lastPathComponent }) {
                    TableColumn("Song") { f in
                        Text(f.songURL.deletingPathExtension().lastPathComponent)
                            .lineLimit(1)
                    }
                    TableColumn("BPM") { f in
                        Text(f.tempoEstimate.map { "\(Int($0))" } ?? "—")
                            .foregroundStyle(f.tempoEstimate == nil ? .tertiary : .primary)
                    }
                    .width(50)
                    TableColumn("Key") { f in
                        Text(keyLabel(f))
                            .foregroundStyle(f.key == nil ? .tertiary : .primary)
                    }
                    .width(50)
                    TableColumn("Loudness") { f in
                        Text(f.averageLoudness.map { String(format: "%.1f dB", $0) } ?? "—")
                            .foregroundStyle(f.averageLoudness == nil ? .tertiary : .primary)
                    }
                    .width(80)
                    TableColumn("Duration") { f in
                        Text(f.durationSeconds.map { formatDuration($0) } ?? "—")
                    }
                    .width(60)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var statusBadge: some View {
        Group {
            switch state {
            case .idle:
                Text("Idle").foregroundStyle(.secondary)
            case .analyzing:
                Label("Analyzing", systemImage: "circle.dotted")
                    .foregroundStyle(.orange)
            case .done(let f):
                Label("\(f.count) songs", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.subheadline)
    }

    private func keyLabel(_ f: TrackFeatures) -> String {
        guard let k = f.key else { return "—" }
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        return "\(names[k])\(f.mode == 0 ? "m" : "")"
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s)
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }
}
#endif
