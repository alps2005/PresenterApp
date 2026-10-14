import AppKit
import Observation
import os
import PresenterCore
import UniformTypeIdentifiers

/// Keeps the operator's project on disk: loads it at launch, autosaves shortly after each edit,
/// and opens or exports project files the operator picks. Never touches live state.
@Observable
final class ProjectPersistence {
    /// `Application Support/Presenter/Project.json`, inside the app's sandbox container.
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Presenter", isDirectory: true)
            .appendingPathComponent("Project.json")
    }

    /// Long enough to batch a burst of typing into one write.
    static let autosaveDelay: Duration = .seconds(1)

    /// The latest load or save problem, for the operator to read and dismiss.
    var problem: String?

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let coordinator: PresentationCoordinator
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: ProjectDocument?

    init(coordinator: PresentationCoordinator, store: ProjectStore, loadProblem: String?) {
        self.coordinator = coordinator
        self.store = store
        problem = loadProblem
        // What's on disk already matches; a sample project isn't written until the operator changes it.
        lastSaved = coordinator.project
        observeProject()
    }

    /// The project to start with: the saved one, else the sample. A file that can't be read is
    /// moved aside first, so autosave never overwrites something the operator might want back.
    static func loadInitialProject(from store: ProjectStore) -> (project: ProjectDocument, problem: String?) {
        do {
            if let project = try store.load() {
                Log.persistence.info("Loaded project from \(store.fileURL.path, privacy: .public)")
                return (project, nil)
            }
            return (.sample(), nil)
        } catch {
            let message = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            Log.persistence.error("Couldn't load project: \(message, privacy: .public)")
            do {
                let moved = try store.quarantine()
                return (.sample(), "\(message) It was moved to \(moved.path) and a sample project was opened instead.")
            } catch {
                return (.sample(), "\(message) A sample project was opened instead.")
            }
        }
    }

    // MARK: - Saving

    /// Writes the project now if it changed since the last save. Called by autosave, ⌘S and on quit.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let project = coordinator.project
        guard project != lastSaved else { return }
        do {
            try store.save(project)
            lastSaved = project
        } catch {
            let message = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            Log.persistence.error("Autosave failed: \(message, privacy: .public)")
            problem = message
        }
    }

    private func observeProject() {
        _ = withObservationTracking {
            coordinator.project
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleSave()
                self?.observeProject()
            }
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    // MARK: - Open and export

    /// Replaces the current project with one the operator picks. The current project is backed up
    /// first, and the audience output is left as it is.
    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Presenter project file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let opened: ProjectDocument
        do {
            guard let project = try ProjectStore(fileURL: url).load() else { return }
            opened = project
        } catch {
            problem = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            return
        }

        saveNow()
        let backup = backUpCurrentProject()
        guard confirmReplace(with: opened, backup: backup) else { return }

        coordinator.replaceProject(opened)
        saveNow()
        Log.persistence.info("Opened project from \(url.path, privacy: .public)")
    }

    /// Writes a copy of the project wherever the operator chooses. Media files aren't included.
    func exportProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(coordinator.project.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectStore(fileURL: url).save(coordinator.project)
            Log.persistence.info("Exported project to \(url.path, privacy: .public)")
        } catch {
            problem = (error as? ProjectStoreError)?.message ?? error.localizedDescription
        }
    }

    /// Copies the current project into `Backups/` next to the project file. Returns the copy, or nil if it failed.
    private func backUpCurrentProject() -> URL? {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let url = store.fileURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("Project-\(stamp).json")
        do {
            try ProjectStore(fileURL: url).save(coordinator.project)
            return url
        } catch {
            Log.persistence.error("Backup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func confirmReplace(with project: ProjectDocument, backup: URL?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Open “\(project.name)”?"
        alert.informativeText = if let backup {
            "It replaces “\(coordinator.project.name)”. A backup of the current project was saved to \(backup.path). The audience output won't change."
        } else {
            "It replaces “\(coordinator.project.name)”. The current project couldn't be backed up, so export it first if you need it."
        }
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
