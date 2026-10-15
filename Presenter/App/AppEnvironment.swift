import Observation
import PresenterCore

/// Requests from menu commands to the operator window.
@Observable
final class OperatorUIState {
    var isAddingSong = false
}

/// The app's long-lived services.
final class AppEnvironment {
    let coordinator: PresentationCoordinator
    let mediaLibrary: MediaLibrary
    let outputManager: OutputManager
    /// Plays video backgrounds on the audience output, independent of any window.
    let playback: MediaPlaybackController
    let persistence: ProjectPersistence
    /// Window-level UI requests that menu commands make, such as opening the New Song sheet.
    let operatorUI = OperatorUIState()

    init() {
        let store = ProjectStore(fileURL: ProjectPersistence.defaultFileURL)
        let initial = ProjectPersistence.loadInitialProject(from: store)
        // Live and cued state always start empty: nothing reaches the audience until the operator takes it live.
        coordinator = PresentationCoordinator(project: initial.project)
        mediaLibrary = MediaLibrary()
        persistence = ProjectPersistence(
            coordinator: coordinator, store: store, mediaDirectory: mediaLibrary.store.directory, loadProblem: initial.problem
        )
        playback = MediaPlaybackController(coordinator: coordinator, mediaLibrary: mediaLibrary)
        outputManager = OutputManager(coordinator: coordinator, mediaLibrary: mediaLibrary, playback: playback)
        preloadProjectMedia()
    }

    /// Keeps every image the project uses decoded and ready, re-checking whenever the project changes.
    private func preloadProjectMedia() {
        let assets = withObservationTracking {
            coordinator.project.mediaAssets
        } onChange: { [weak self] in
            Task { @MainActor in self?.preloadProjectMedia() }
        }
        mediaLibrary.preload(assets)
    }
}
