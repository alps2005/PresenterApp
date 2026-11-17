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

    @ObservationIgnored private(set) var updater: SPUUpdater?
    @ObservationIgnored private var userDriver: PresenterUserDriver?
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
        // What SPUStandardUpdaterController does, with Presenter's own wording for a check that can't reach GitHub.
        let userDriver = PresenterUserDriver(hostBundle: .main, delegate: self)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
        self.userDriver = userDriver
        self.updater = updater
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        do {
            try updater.start()
        } catch {
            Log.app.error("The updater couldn't start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sparkle can't replace a copy running from the disk image, or one macOS moved to a hidden read-only place
    /// because it wasn't dragged into a folder in Finder ("App Translocation"). Says so once per launch.
    func warnIfThisCopyCantUpdate(at bundleURL: URL = Bundle.main.bundleURL) {
        guard isAvailable else { return }
        let isReadOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        guard isReadOnly || bundleURL.path.contains("/AppTranslocation/") else { return }
        Log.app.info("Running from a read-only place; updates can't install")
        let alert = NSAlert()
        alert.messageText = String(localized: "Move Presenter to Applications to get updates")
        alert.informativeText = isReadOnly && !bundleURL.path.contains("/AppTranslocation/")
            ? String(localized: "Presenter is running from the disk image, so it can't update itself. Quit, drag Presenter onto the Applications shortcut, eject the disk image and open Presenter from Applications.")
            : "macOS is running this copy from a temporary place, so it can't update itself. Quit, then in Finder drag Presenter into the Applications folder and open it from there."
        alert.runModal()
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
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
        alert.messageText = String(localized: "Presenter \(item.displayVersionString) will install when the service is over")
        alert.informativeText = String(localized: "Presenter restarts to install it once nothing is live and the outputs are off. What's on screen now stays as it is.")
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

/// Sparkle's standard windows, except when a check can't reach GitHub: Sparkle then says only "An error occurred in
/// retrieving update information", which reads like something is wrong with Presenter. The error is reworded and
/// Sparkle still shows it, so its "Checking for updates" window closes as usual.
final class PresenterUserDriver: SPUStandardUserDriver {
    override func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        guard Self.isConnectionProblem(error) else {
            super.showUpdaterError(error, acknowledgement: acknowledgement)
            return
        }
        Log.app.info("Update check couldn't reach the server: \(String(describing: error), privacy: .public)")
        let reworded = NSError(domain: (error as NSError).domain, code: (error as NSError).code, userInfo: [
            NSLocalizedDescriptionKey: String(localized: "Presenter couldn't reach the update server"),
            NSLocalizedRecoverySuggestionErrorKey: String(localized: "Check that this Mac is connected to the internet, then choose Presenter › Check for Updates… to try again. Nothing is wrong with Presenter or your project."),
            NSUnderlyingErrorKey: error,
        ])
        super.showUpdaterError(reworded, acknowledgement: acknowledgement)
    }

    /// True when the error, or one under it, says the network couldn't be reached: offline, timed out, no DNS.
    static func isConnectionProblem(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSURLErrorDomain, connectionCodes.contains(error.code) { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    private static let connectionCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
        NSURLErrorDataNotAllowed, NSURLErrorSecureConnectionFailed,
    ]
}
