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

    /// Saves before agreeing to quit, so a failed save can still stop the quit instead of losing the operator's edits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let persistence = environment.persistence
        if persistence.saveNow() { return .terminateNow }

        // This alert explains the failure; don't repeat it in the operator window's problem alert.
        let problem = persistence.problem ?? ""
        persistence.problem = nil
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Your changes couldn't be saved"
        alert.informativeText = """
            \(problem) If you quit now, changes since the last save are lost. \
            To keep them, cancel and use Export Project… to save a copy somewhere else.
            """
        alert.addButton(withTitle: "Cancel")
        let quit = alert.addButton(withTitle: "Quit Anyway")
        quit.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Log.app.error("Quit without saving after a failed save")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.persistence.saveNow()
        environment.outputManager.hideAll()
    }
}
