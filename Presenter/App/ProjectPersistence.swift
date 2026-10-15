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
    /// What's running while an export or open reads or writes media, e.g. "Exporting…". Nil when idle.
    private(set) var activity: String?

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let backups: ProjectBackups
    @ObservationIgnored private let coordinator: PresentationCoordinator
    /// Where imported media lives; exports read from it and opened archives write into it.
    @ObservationIgnored private let mediaDirectory: URL
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: ProjectDocument?

    init(coordinator: PresentationCoordinator, store: ProjectStore, mediaDirectory: URL, loadProblem: String?) {
        self.coordinator = coordinator
        self.store = store
        self.mediaDirectory = mediaDirectory
        backups = ProjectBackups(projectFileURL: store.fileURL)
        problem = loadProblem
        // What's on disk already matches; a sample project isn't written until the operator changes it.
        lastSaved = coordinator.project
        observeProject()
    }

    /// The project to start with (see `ProjectLoader`), logging what happened.
    static func loadInitialProject(from store: ProjectStore) -> (project: ProjectDocument, problem: String?) {
        let outcome = ProjectLoader.loadInitialProject(from: store, backups: ProjectBackups(projectFileURL: store.fileURL))
        if outcome.loadedFromDisk {
            Log.persistence.info("Loaded project from \(store.fileURL.path, privacy: .public)")
        }
        if let problem = outcome.problem {
            Log.persistence.error("Couldn't load project: \(problem, privacy: .public)")
        }
        if let backupError = outcome.backupError {
            Log.persistence.error("Launch backup failed: \(backupError, privacy: .public)")
        }
        return (outcome.project, outcome.problem)
    }

    // MARK: - Saving

    /// Writes the project now if it changed since the last save. Called by autosave, ⌘S and on quit.
    /// Returns false if the save failed; `problem` then says why.
    @discardableResult
    func saveNow() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        let project = coordinator.project
        guard project != lastSaved else { return true }
        do {
            try store.save(project)
            lastSaved = project
            return true
        } catch {
            let message = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            Log.persistence.error("Autosave failed: \(message, privacy: .public)")
            problem = message
            return false
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
        guard activity == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Presenter project file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let mediaDirectory = mediaDirectory
        activity = "Opening “\(url.deletingPathExtension().lastPathComponent)”…"
        Task {
            // An exported project carries its media; it goes into the media folder so its slides show it.
            // (If the operator then cancels, the copied files are simply unused.) Reading and decoding a
            // project with videos can take a while, so it happens off the main thread.
            let result = await Task.detached {
                Result { try ProjectArchive.open(Data(contentsOf: url), mediaDirectory: mediaDirectory) }
            }.value
            activity = nil
            switch result {
            case .success(let opened): finishOpening(opened, from: url)
            case .failure(let error): problem = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            }
        }
    }

    private func finishOpening(_ opened: ProjectDocument, from url: URL) {
        saveNow()
        let backup = backUpCurrentProject()
        guard confirmReplace(with: opened, backup: backup) else { return }

        coordinator.replaceProject(opened)
        saveNow()
        Log.persistence.info("Opened project from \(url.path, privacy: .public)")
    }

    /// Writes a copy of the project, with the images and videos it uses, wherever the operator chooses.
    func exportProject() {
        guard activity == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(coordinator.project.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let project = coordinator.project
        let mediaDirectory = mediaDirectory
        activity = "Exporting “\(project.name)”…"
        Task {
            // Media is embedded in the file, so a project with videos is large; encode and write off the main thread.
            let result = await Task.detached {
                Result { try ProjectArchive.export(project, mediaDirectory: mediaDirectory).write(to: url, options: .atomic) }
            }.value
            activity = nil
            switch result {
            case .success: Log.persistence.info("Exported project to \(url.path, privacy: .public)")
            case .failure(let error): problem = (error as? ProjectStoreError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Saves the current project into `Backups/` next to the project file. Returns the copy, or nil if it failed.
    private func backUpCurrentProject() -> URL? {
        do {
            return try backups.save(coordinator.project)
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
