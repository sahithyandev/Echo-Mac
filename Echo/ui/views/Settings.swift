//
//  Settings.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-18.
//

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
                        Button("Choose…") {
                            pickFolder()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 400)
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
