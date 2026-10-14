import Observation
import PresenterCore

/// The app's long-lived services.
final class AppEnvironment {
    let coordinator: PresentationCoordinator
    let mediaLibrary: MediaLibrary
    let outputManager: OutputManager
    let persistence: ProjectPersistence

    init() {
        let store = ProjectStore(fileURL: ProjectPersistence.defaultFileURL)
        let initial = ProjectPersistence.loadInitialProject(from: store)
        // Live and cued state always start empty: nothing reaches the audience until the operator takes it live.
        coordinator = PresentationCoordinator(project: initial.project)
        persistence = ProjectPersistence(coordinator: coordinator, store: store, loadProblem: initial.problem)
        mediaLibrary = MediaLibrary()
        outputManager = OutputManager(coordinator: coordinator, mediaLibrary: mediaLibrary)
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
