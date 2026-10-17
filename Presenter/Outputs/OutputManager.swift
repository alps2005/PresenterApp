import AppKit
import os
import Observation
import PresenterCore
import SwiftUI

/// Tracks connected displays and places the audience and stage outputs as `OutputPlanner` decides.
@Observable
final class OutputManager {
    private(set) var planner = OutputPlanner(displays: DisplayDiscovery.currentDisplays())

    @ObservationIgnored private var controllers: [OutputRole: OutputWindowController] = [:]
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary, playback: MediaPlaybackController) {
        controllers[.audience] = OutputWindowController(title: OutputRole.audience.title) {
            AnyView(
                AudienceOutputView(coordinator: coordinator)
                    .environment(mediaLibrary)
                    .environment(playback)
                    .environment(\.showsLiveVideo, true)
            )
        }
        controllers[.stage] = OutputWindowController(title: OutputRole.stage.title) {
            AnyView(StageOutputView(coordinator: coordinator).environment(mediaLibrary))
        }
        for role in OutputRole.allCases {
            controllers[role]?.onUserClosedWindow = { [weak self] in
                self?.planner.hide(role)
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    var displays: [DisplayInfo] { planner.displays }

    // MARK: Audience (the defaults most callers want)

    var isEnabled: Bool { isEnabled(.audience) }
    var target: OutputTarget { target(.audience) }
    var status: OutputStatus { status(.audience) }
    var fullScreenCandidates: [DisplayInfo] { fullScreenCandidates(.audience) }

    // MARK: Per output

    func isEnabled(_ role: OutputRole) -> Bool { planner.isEnabled(role) }
    func target(_ role: OutputRole) -> OutputTarget { planner.target(role) }
    func status(_ role: OutputRole) -> OutputStatus { planner.status(role) }
    func fullScreenCandidates(_ role: OutputRole) -> [DisplayInfo] { planner.fullScreenCandidates(role) }
    func displaysInUse(byOtherThan role: OutputRole) -> [DisplayInfo] { planner.displaysInUse(byOtherThan: role) }

    func show(_ target: OutputTarget, for role: OutputRole = .audience) {
        planner.show(target, for: role)
        apply(role)
    }

    func hide(_ role: OutputRole = .audience) {
        planner.hide(role)
        apply(role)
    }

    func hideAll() {
        for role in OutputRole.allCases { hide(role) }
    }

    func toggle(_ role: OutputRole = .audience) {
        planner.toggle(role)
        apply(role)
    }

    func operatorWindowMoved(to screen: NSScreen?) {
        planner.operatorDisplayID = screen.flatMap(DisplayDiscovery.displayID(of:))
    }

    private func screensChanged() {
        planner.displays = DisplayDiscovery.currentDisplays()
        Log.output.info("Displays changed: \(self.planner.displays.map(\.name), privacy: .public)")
        for role in OutputRole.allCases { apply(role) }
    }

    private func apply(_ role: OutputRole) {
        guard let controller = controllers[role] else { return }
        switch planner.placement(role) {
        case .hidden:
            controller.hide()
            if case .displayMissing(let name) = planner.status(role) {
                Log.output.error("\(role.title, privacy: .public) display \(name, privacy: .public) is not connected")
            }
        case .windowed:
            controller.showWindowed()
        case .fullScreen(let id):
            if let screen = DisplayDiscovery.screen(for: id) {
                controller.showFullScreen(on: screen, displayID: id)
            } else {
                controller.hide()
                Log.output.error("\(role.title, privacy: .public) display \(id, privacy: .public) has no screen")
            }
        }
    }
}
