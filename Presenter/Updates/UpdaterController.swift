import AppKit
import Observation
import os
import Sparkle

/// Checks GitHub for new versions with Sparkle, once a day, and asks before installing. It never interrupts a
/// service: while anything is live or an output is on, a scheduled check shows no window, only a quiet "Update to…"
/// item, and an update the operator accepts waits to relaunch until nothing is live.
@Observable
final class UpdaterController: NSObject {
    /// False while a check or an install is under way, for the menu item.
    private(set) var canCheckForUpdates = false
    /// A version Sparkle found but didn't show, because Presenter was presenting.
    private(set) var availableVersion: String?
    /// Whether this build updates at all: Debug builds and builds without a public key don't.
    let isAvailable: Bool

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let isPresenting: () -> Bool
    @ObservationIgnored private var pendingRelaunch: (() -> Void)?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(isPresenting: @escaping () -> Bool) {
        self.isPresenting = isPresenting
        let info = Bundle.main.infoDictionary ?? [:]
        isAvailable = !(info["SUFeedURL"] as? String ?? "").isEmpty && !(info["SUPublicEDKey"] as? String ?? "").isEmpty
        super.init()
        guard isAvailable else {
            Log.app.info("Updates are off in this build")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }

    var updater: SPUUpdater? { controller?.updater }

    /// Sparkle can't replace a copy running from the disk image, or one macOS moved to a hidden read-only place
    /// because it wasn't dragged into a folder in Finder ("App Translocation"). Says so once per launch.
    func warnIfThisCopyCantUpdate(at bundleURL: URL = Bundle.main.bundleURL) {
        guard isAvailable else { return }
        let isReadOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        guard isReadOnly || bundleURL.path.contains("/AppTranslocation/") else { return }
        Log.app.info("Running from a read-only place; updates can't install")
        let alert = NSAlert()
        alert.messageText = "Move Presenter to Applications to get updates"
        alert.informativeText = isReadOnly && !bundleURL.path.contains("/AppTranslocation/")
            ? "Presenter is running from the disk image, so it can't update itself. Quit, drag Presenter onto the Applications shortcut, eject the disk image and open Presenter from Applications."
            : "macOS is running this copy from a temporary place, so it can't update itself. Quit, then in Finder drag Presenter into the Applications folder and open it from there."
        alert.runModal()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Runs the postponed relaunch once nothing is live and every output is off.
    private func relaunchWhenFree() {
        let busy = withObservationTracking {
            isPresenting()
        } onChange: { [weak self] in
            Task { @MainActor in self?.relaunchWhenFree() }
        }
        guard !busy, let relaunch = pendingRelaunch else { return }
        pendingRelaunch = nil
        Log.app.info("Nothing is live: installing the update")
        relaunch()
    }
}

extension UpdaterController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isPresenting() else { return false }
        pendingRelaunch = installHandler
        let alert = NSAlert()
        alert.messageText = "Presenter \(item.displayVersionString) will install when the service is over"
        alert.informativeText = "Presenter restarts to install it once nothing is live and the outputs are off. What's on screen now stays as it is."
        alert.runModal()
        relaunchWhenFree()
        return true
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only right after launch or when Presenter comes to the front, and
    /// never while presenting. Otherwise the quiet "Update to…" item does.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus && !isPresenting()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { availableVersion = update.displayVersionString }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
