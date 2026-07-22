import SwiftUI

struct Settings: View {
    @EnvironmentObject private var playerViewModel: AudioPlayerViewModel
    @EnvironmentObject private var libraryViewModel: MusicLibraryViewModel
    // Each element is a group of tracks sharing the same stableId (i.e. same recording).
    @State private var duplicateGroups: [[TrackFeatures]] = []

    var body: some View {
        Form {
            Section("Libraries") {
                ForEach(libraryViewModel.libraries) { library in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("", text: nameBinding(for: library))
                                .textFieldStyle(.plain)
                                .font(.body)
                                .labelsHidden()
                                .accessibilityLabel("Library name")
                            Text(library.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            libraryViewModel.removeLibrary(library.id)
                        }
                    }
                }
                Button("Add Library…") { addLibrary() }
                Button("Rescan Libraries") {
                    libraryViewModel.reload()
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
        let grouped = Dictionary(grouping: features.filter { $0.stableId != nil && FileManager.default.fileExists(atPath: $0.songURL.path(percentEncoded: false)) }, by: { $0.stableId! })
        duplicateGroups = grouped.values
            .filter { $0.count > 1 }
            .sorted { groupTitle($0) < groupTitle($1) }
    }

    private func groupTitle(_ group: [TrackFeatures]) -> String {
        group.first.map { $0.songURL.deletingPathExtension().lastPathComponent } ?? "Unknown"
    }

    private func nameBinding(for library: Library) -> Binding<String> {
        Binding(
            get: { library.name },
            set: { libraryViewModel.renameLibrary(library.id, to: $0) }
        )
    }

    private func addLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            libraryViewModel.addLibraries(panel.urls)
        }
    }
}

#Preview {
    Settings()
        .environmentObject(AudioPlayerViewModel())
        .environmentObject(MusicLibraryViewModel())
}
