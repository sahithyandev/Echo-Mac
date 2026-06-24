import SwiftUI
import EchoCore

struct RecommendedSongsStrip: View {
    let songs: [Song]
    let onTap: (Song) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Up Next")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(songs) { song in
                        Button { onTap(song) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                SongArtworkView(song: song, size: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(song.title)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }
}
