import SwiftUI

@main
struct PresenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // First, so it's the window Presenter opens with (AppDelegate keeps macOS from restoring the operator
        // window over it).
        Window("Welcome to Presenter", id: WelcomeView.windowID) {
            WelcomeView(
                coordinator: appDelegate.environment.coordinator,
                outputManager: appDelegate.environment.outputManager,
                persistence: appDelegate.environment.persistence,
                ui: appDelegate.environment.operatorUI,
                updater: appDelegate.environment.updater
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("1", modifiers: [.command, .shift])

        Window("Presenter", id: "operator") {
            OperatorView(
                coordinator: appDelegate.environment.coordinator,
                outputManager: appDelegate.environment.outputManager,
                persistence: appDelegate.environment.persistence,
                ui: appDelegate.environment.operatorUI
            )
            .frame(
                minWidth: OperatorView.minimumWindowSize.width,
                minHeight: OperatorView.minimumWindowSize.height
            )
            .environment(appDelegate.environment.mediaLibrary)
            .environment(appDelegate.environment.playback)
            .environment(appDelegate.environment.audio)
            .environment(appDelegate.environment.bibleLibrary)
            .environment(appDelegate.environment.audioOutput)
        }
        .defaultSize(width: 1280, height: 800)
        // Make the window enforce the content's minimum size instead of letting panes get clipped.
        .windowResizability(.contentMinSize)
        .commands {
            PresenterCommands(
                coordinator: appDelegate.environment.coordinator,
                outputManager: appDelegate.environment.outputManager,
                persistence: appDelegate.environment.persistence,
                ui: appDelegate.environment.operatorUI
            )
            UpdateCommands(updater: appDelegate.environment.updater)
        }

        Settings {
            TabView {
                UpdateSettingsView(updater: appDelegate.environment.updater)
                    .tabItem { Label("General", systemImage: "gearshape") }
                AudioSettingsView(output: appDelegate.environment.audioOutput)
                    .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            }
        }
    }
}
