import SwiftUI
import EchoCore

struct SongRow: View {
    let song: Song
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            SongArtworkView(song: song, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: AppSpacing.sm)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        switch (song.artist, song.album) {
        case (let a?, let b?): return "\(a) — \(b)"
        case (let a?, nil):    return a
        case (nil, let b?):    return b
        case (nil, nil):       return nil
        }
    }
}
