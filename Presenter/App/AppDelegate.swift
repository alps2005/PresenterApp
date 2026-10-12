import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created once and kept for the app's lifetime, independent of any window or view.
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Launched")
    }

    /// Closing the operator window must not take down the audience output mid-service.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.outputManager.hide()
    }
}
