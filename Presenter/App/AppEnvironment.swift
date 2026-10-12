import Observation
import PresenterCore

/// The app's long-lived services. Persistence will replace the sample project in a later milestone.
final class AppEnvironment {
    let coordinator: PresentationCoordinator
    let mediaLibrary: MediaLibrary
    let outputManager: OutputManager

    init() {
        coordinator = PresentationCoordinator(project: .sample())
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
