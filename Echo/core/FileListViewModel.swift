//
//  FileListViewModel.swift
//  Echo
//
//  Created by Sahithyan Kandathasan on 2026-06-16.
//

import Foundation
import Combine

@MainActor
class FileListViewModel: ObservableObject {
    @Published var files: [URL] = []
    @Published var errorMessage: String?

    func loadFiles(at directoryURL: URL) {
        let fm = FileManager.default

        do {
            files = try fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            print("Loaded \(files.count) files")
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading files: \(error)")
        }
    }
}
