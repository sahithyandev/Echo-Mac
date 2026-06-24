import EchoCore
import SwiftUI

struct Settings: View {
    @AppStorage("libraryDirectory") private var libraryPath: String = "/Users/\(NSUserName())/Music"
    @EnvironmentObject private var playerViewModel: AudioPlayerViewModel
    // Each element is a group of tracks sharing the same stableId (i.e. same recording).
    @State private var duplicateGroups: [[TrackFeatures]] = []

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Location") {
                    HStack {
                        Text(libraryPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { pickFolder() }
                    }
                }
            }

            if !duplicateGroups.isEmpty {
                Section {
                    ForEach(duplicateGroups.indices, id: \.self) { gi in
                        DisclosureGroup {
                            ForEach(duplicateGroups[gi], id: \.songURL) { track in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.songURL.deletingPathExtension().lastPathComponent)
                                        .font(.body)
                                    Text(track.songURL.deletingLastPathComponent().path(percentEncoded: false))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(AppColor.accent)
                                Text(groupTitle(duplicateGroups[gi]))
                                Spacer()
                                Text("\(duplicateGroups[gi].count) copies")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Duplicate Tracks")
                } footer: {
                    Text("These files share the same acoustic fingerprint. Keep one and delete the rest.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 400)
        // Tint is inherited from Root; explicit here for the preview
        .tint(AppColor.accent)
        .task { await loadDuplicates() }
    }

    private func loadDuplicates() async {
        let features = await playerViewModel.allFeatures()
        let grouped = Dictionary(grouping: features.filter { $0.stableId != nil }, by: { $0.stableId! })
        duplicateGroups = grouped.values
            .filter { $0.count > 1 }
            .sorted { groupTitle($0) < groupTitle($1) }
    }

    private func groupTitle(_ group: [TrackFeatures]) -> String {
        group.first.map { $0.songURL.deletingPathExtension().lastPathComponent } ?? "Unknown"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            libraryPath = url.path
        }
    }
}

#Preview {
    Settings()
        .environmentObject(AudioPlayerViewModel())
}
