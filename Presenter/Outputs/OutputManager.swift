import AppKit
import os
import Observation
import PresenterCore

enum OutputTarget: Hashable {
    case windowed
    case display(CGDirectDisplayID)
}

enum OutputStatus: Equatable {
    case off
    case windowed
    case fullScreen(displayName: String)
    /// The chosen display is gone. Output is hidden and comes back if the display reconnects.
    case displayMissing(displayName: String)
}

/// Tracks connected displays and places the audience output according to the operator's choice.
@Observable
final class OutputManager {
    private(set) var displays: [DisplayInfo] = DisplayDiscovery.currentDisplays()
    private(set) var target: OutputTarget = .windowed
    /// The operator's intent. The window may still be hidden if the chosen display is missing.
    private(set) var isEnabled = false
    /// The display showing the operator window. Full-screen output is never offered there.
    private(set) var operatorDisplayID: CGDirectDisplayID?
    private var targetDisplayName = ""

    @ObservationIgnored private let controller: AudienceOutputController
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary) {
        controller = AudienceOutputController(coordinator: coordinator, mediaLibrary: mediaLibrary)
        controller.onUserClosedWindow = { [weak self] in
            self?.isEnabled = false
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    var status: OutputStatus {
        guard isEnabled else { return .off }
        switch target {
        case .windowed:
            return .windowed
        case .display(let id):
            return displays.contains { $0.id == id }
                ? .fullScreen(displayName: targetDisplayName)
                : .displayMissing(displayName: targetDisplayName)
        }
    }

    /// Displays that can take full-screen output without covering the operator window.
    var fullScreenCandidates: [DisplayInfo] {
        let operatorID = operatorDisplayID ?? displays.first(where: \.isPrimary)?.id
        return displays.filter { $0.id != operatorID }
    }

    func show(_ target: OutputTarget) {
        if case .display(let id) = target, let display = displays.first(where: { $0.id == id }) {
            targetDisplayName = display.name
        }
        self.target = target
        isEnabled = true
        apply()
    }

    func hide() {
        isEnabled = false
        apply()
    }

    func toggle() {
        isEnabled ? hide() : show(target)
    }

    func operatorWindowMoved(to screen: NSScreen?) {
        operatorDisplayID = screen.flatMap(DisplayDiscovery.displayID(of:))
    }

    private func screensChanged() {
        displays = DisplayDiscovery.currentDisplays()
        Log.output.info("Displays changed: \(self.displays.map(\.name), privacy: .public)")
        apply()
    }

    private func apply() {
        guard isEnabled else {
            controller.hide()
            return
        }
        switch target {
        case .windowed:
            controller.showWindowed()
        case .display(let id):
            if let screen = DisplayDiscovery.screen(for: id) {
                controller.showFullScreen(on: screen, displayID: id)
            } else {
                controller.hide()
                Log.output.error("Output display \(self.targetDisplayName, privacy: .public) is not connected")
            }
        }
    }
}
