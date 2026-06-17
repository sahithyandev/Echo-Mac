import Foundation
import Combine

@MainActor
class MusicLibraryViewModel: ObservableObject {
    @Published var songs: [Song] = []
    @Published var errorMessage: String?

    private let library = MusicLibrary()

    func load(from directoryURL: URL) {
        do {
            songs = try library.songs(in: directoryURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
