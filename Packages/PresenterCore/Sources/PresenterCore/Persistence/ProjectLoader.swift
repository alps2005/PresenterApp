import Foundation

/// Chooses the project to start with: the saved one, else the starter. UI-free; the app shows `problem`.
public enum ProjectLoader {
    public struct Outcome: Sendable {
        public var project: ProjectDocument
        /// Why the saved project couldn't be used, for the operator to read. Nil when all went well.
        public var problem: String?
        /// True when `project` came from the file, so it already matches what's on disk.
        public var loadedFromDisk: Bool
        /// Set if the launch backup failed. Loading still succeeded; this is only worth logging.
        public var backupError: String?
    }

    /// Loads the saved project and backs it up (skipped when unchanged since the last backup). A file that
    /// can't be read is moved aside first, so autosave never overwrites something the operator might want back.
    public static func loadInitialProject(
        from store: ProjectStore,
        backups: ProjectBackups,
        now: Date = .now,
        starter: () -> ProjectDocument = { .starter() }
    ) -> Outcome {
        do {
            guard let project = try store.load() else {
                return Outcome(project: starter(), problem: nil, loadedFromDisk: false)
            }
            var backupError: String?
            do {
                try backups.backUpFile(at: store.fileURL, now: now)
            } catch {
                backupError = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            }
            return Outcome(project: project, problem: nil, loadedFromDisk: true, backupError: backupError)
        } catch {
            let message = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            let problem: String
            do {
                let moved = try store.quarantine(now: now)
                problem = "\(message) It was moved to \(moved.path) and a new, empty project was opened instead."
            } catch {
                problem = "\(message) A new, empty project was opened instead."
            }
            return Outcome(project: starter(), problem: problem, loadedFromDisk: false)
        }
    }
}
