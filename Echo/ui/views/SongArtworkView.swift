import SwiftUI
import AVFoundation
import AppKit

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
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in items {
            guard item.commonKey == .commonKeyArtwork else { continue }
            guard let data = try? await item.load(.dataValue) else { continue }
            return NSImage(data: data)
        }
        return nil
    }
}
