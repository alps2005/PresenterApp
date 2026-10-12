import PresenterCore

/// The app's long-lived services. Persistence will replace the sample project in a later milestone.
final class AppEnvironment {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager

    init() {
        coordinator = PresentationCoordinator(project: .sample())
        outputManager = OutputManager(coordinator: coordinator)
    }
}
