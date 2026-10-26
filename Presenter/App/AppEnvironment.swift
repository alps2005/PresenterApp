import Foundation
import Observation
import os
import PresenterCore

/// Requests from menu commands to the operator window.
@Observable
final class OperatorUIState {
    var isAddingSong = false
    var isImportingSongs = false
    var isAddingScripture = false
    var isShowingShows = false
    var isShowingCCLIReport = false
    /// Asks the operator window to import a PDF's pages as a presentation.
    var isImportingPDF = false
    var preServiceCheck: PreServiceCheckMode?
    /// The check runs once at launch, when the operator window first appears.
    var hasRunLaunchCheck = false
    /// The audience output whose look is being edited.
    var editingLookRole: OutputRole?
    /// Whether the operator window is on screen; the welcome window quits Presenter when closed without it.
    var isOperatorWindowOpen = false
    /// Set once the operator window has appeared, so the welcome window only skips itself at launch.
    var hasShownOperatorWindow = false
}

/// The app's long-lived services.
final class AppEnvironment {
    let coordinator: PresentationCoordinator
    let mediaLibrary: MediaLibrary
    /// Imported Bible translations, kept outside the project.
    let bibleLibrary = BibleLibrary()
    let outputManager: OutputManager
    /// Plays video backgrounds on the audience output, independent of any window.
    let playback: MediaPlaybackController
    /// Plays audio cues, soundtracks and tracks from the audio bin.
    let audio: AudioPlaybackController
    /// The sound output music and video play through, chosen in Settings.
    let audioOutput = AudioOutput()
    /// Moves the live slide on when its Slideshow or Go To Next countdown ends.
    let autoAdvance: AutoAdvanceDriver
    let persistence: ProjectPersistence
    /// Window-level UI requests that menu commands make, such as opening the New Song sheet.
    let operatorUI = OperatorUIState()
    /// Checks for new versions; never interrupts a service.
    let updater: UpdaterController

    init() {
        let store = ProjectStore(fileURL: ProjectPersistence.defaultFileURL)
        let initial = ProjectPersistence.loadInitialProject(from: store)
        // Live and cued state always start empty: nothing reaches the audience until the operator takes it live.
        coordinator = PresentationCoordinator(project: initial.project)
        mediaLibrary = MediaLibrary()
        persistence = ProjectPersistence(
            coordinator: coordinator, store: store, mediaDirectory: mediaLibrary.store.directory, loadProblem: initial.problem
        )
        playback = MediaPlaybackController(coordinator: coordinator, mediaLibrary: mediaLibrary, output: audioOutput)
        audio = AudioPlaybackController(coordinator: coordinator, mediaLibrary: mediaLibrary, output: audioOutput)
        outputManager = OutputManager(coordinator: coordinator, mediaLibrary: mediaLibrary, playback: playback)
        autoAdvance = AutoAdvanceDriver(coordinator: coordinator, playback: playback, mediaLibrary: mediaLibrary)
        updater = UpdaterController { [coordinator, outputManager] in
            coordinator.state.isPresenting(outputsShowing: outputManager.isAnyOutputOn)
        }
        // Songs count for the CCLI report when they go live. Written off the main thread: it reads the log.
        coordinator.onSongWentLive = { presentation in
            let log = SongUsageLog.app
            let now = Date()
            Task {
                let failure = await Task.detached(priority: .utility) { () -> String? in
                    do {
                        try log.record(presentation, at: now)
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                if let failure { Log.persistence.error("Song usage not recorded: \(failure, privacy: .public)") }
            }
        }
        preloadProjectMedia()
        if initial.loadedFromDisk {
            removeDeletedMedia(keeping: initial.project, backups: ProjectBackups(projectFileURL: store.fileURL))
        }
    }

    /// Deletes the files of media deleted from the project. Done at launch, when Undo can no longer bring them
    /// back; files a backup or a project file moved aside still uses are kept. Skipped when the saved project
    /// couldn't be loaded, so a failed load never empties the media folder.
    private func removeDeletedMedia(keeping project: ProjectDocument, backups: ProjectBackups) {
        let store = mediaLibrary.store
        let inUse = Set(project.mediaAssets.map(\.storedFilename))
        // Listed now, so a file imported while the backups are read is never a candidate.
        let candidates = store.filenames()
        Task {
            let removed = await Task.detached(priority: .utility) {
                store.removeFiles(among: candidates, keeping: inUse.union(backups.referencedMediaFilenames()))
            }.value
            if !removed.isEmpty {
                Log.persistence.info("Removed \(removed.count) deleted media files")
            }
        }
    }

    /// Keeps every image the project uses decoded and ready, re-checking whenever the project changes.
    private func preloadProjectMedia() {
        let assets = withObservationTracking {
            coordinator.project.mediaAssets.filter { $0.kind != .audio }
        } onChange: { [weak self] in
            Task { @MainActor in self?.preloadProjectMedia() }
        }
        mediaLibrary.preload(assets)
    }
}
