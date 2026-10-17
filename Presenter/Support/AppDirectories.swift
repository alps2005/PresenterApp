import Foundation

enum AppDirectories {
    /// `Application Support/Presenter`, inside the app's sandbox container: the project, its media and backups.
    ///
    /// Debug builds can be pointed elsewhere with `-PresenterDebugDataDirectory <path>`, so layout checks and
    /// scripted tests (scripts/layout-screenshots.sh) run on their own copy and never touch the operator's show.
    static var data: URL {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "PresenterDebugDataDirectory"), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("Presenter", isDirectory: true)
    }
}
