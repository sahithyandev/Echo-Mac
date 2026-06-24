import SwiftUI

struct Settings: View {
    @AppStorage("libraryDirectory") private var libraryPath: String = "/Users/\(NSUserName())/Music"

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
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 400)
        // Tint is inherited from Root; explicit here for the preview
        .tint(AppColor.accent)
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
}
