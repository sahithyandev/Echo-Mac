import SwiftUI
import AVFoundation
import AppKit

// ponytail: limits concurrent AVURLAsset disk reads to prevent I/O contention on initial load
private actor LoadThrottle {
    static let shared = LoadThrottle(4)
    private var slots: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { slots = n }
    func acquire() async {
        guard slots > 0 else { await withCheckedContinuation { waiters.append($0) }; return }
        slots -= 1
    }
    func release() { waiters.isEmpty ? (slots += 1) : waiters.removeFirst().resume() }
}

struct SongArtworkView: View {
    let song: Song
    let size: CGFloat

    @State private var artwork: NSImage?

    var body: some View {
        ZStack {
            AppColor.tealDark

            Image(systemName: "music.note")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(AppColor.tealLight)
                .opacity(artwork == nil ? 1 : 0)

            if let image = artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .animation(.easeInOut(duration: 0.25), value: artwork == nil)
        .task(id: song.url) {
            artwork = await loadArtwork(from: song.url)
        }
    }

    private func loadArtwork(from url: URL) async -> NSImage? {
        if let cached = ArtworkCache.shared.get(url) { return cached }
        await LoadThrottle.shared.acquire()
        defer { Task { await LoadThrottle.shared.release() } }
        if let cached = ArtworkCache.shared.get(url) { return cached }  // re-check after queuing
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items {
            guard item.commonKey == .commonKeyArtwork else { continue }
            guard let data = try? await item.load(.dataValue) else { continue }
            guard let image = ArtworkCache.decode(data) else { continue }
            ArtworkCache.shared.set(image, for: url)
            return image
        }
        return nil
    }
}
