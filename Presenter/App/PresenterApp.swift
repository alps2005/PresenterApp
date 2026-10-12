import SwiftUI

@main
struct PresenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Presenter", id: "operator") {
            OperatorView(
                coordinator: appDelegate.environment.coordinator,
                outputManager: appDelegate.environment.outputManager
            )
            .frame(
                minWidth: OperatorView.minimumWindowSize.width,
                minHeight: OperatorView.minimumWindowSize.height
            )
            .environment(appDelegate.environment.mediaLibrary)
        }
        .defaultSize(width: 1280, height: 800)
        // Make the window enforce the content's minimum size instead of letting panes get clipped.
        .windowResizability(.contentMinSize)
        .commands {
            PresenterCommands(
                coordinator: appDelegate.environment.coordinator,
                outputManager: appDelegate.environment.outputManager
            )
        }
    }
}
