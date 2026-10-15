import AppKit
import os
import Observation
import PresenterCore
import SwiftUI

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

/// Which output a command is for. The stage display never shows audience content controls, and the audience
/// never sees stage-only information.
enum OutputRole: CaseIterable, Hashable {
    case audience
    case stage

    var title: String {
        switch self {
        case .audience: "Audience Output"
        case .stage: "Stage Display"
        }
    }
}

/// Tracks connected displays and places the audience and stage outputs according to the operator's choices.
@Observable
final class OutputManager {
    private struct Channel {
        var target: OutputTarget = .windowed
        /// The operator's intent. The window may still be hidden if the chosen display is missing.
        var isEnabled = false
        var targetDisplayName = ""
    }

    private(set) var displays: [DisplayInfo] = DisplayDiscovery.currentDisplays()
    /// The display showing the operator window. Full-screen output is never offered there.
    private(set) var operatorDisplayID: CGDirectDisplayID?
    private var channels: [OutputRole: Channel] = [.audience: Channel(), .stage: Channel()]

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
                self?.channels[role]?.isEnabled = false
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

    // MARK: Audience (the defaults most callers want)

    var isEnabled: Bool { isEnabled(.audience) }
    var target: OutputTarget { target(.audience) }
    var status: OutputStatus { status(.audience) }
    var fullScreenCandidates: [DisplayInfo] { fullScreenCandidates(.audience) }

    // MARK: Per output

    func isEnabled(_ role: OutputRole) -> Bool { channels[role]?.isEnabled ?? false }
    func target(_ role: OutputRole) -> OutputTarget { channels[role]?.target ?? .windowed }

    func status(_ role: OutputRole) -> OutputStatus {
        guard let channel = channels[role], channel.isEnabled else { return .off }
        switch channel.target {
        case .windowed:
            return .windowed
        case .display(let id):
            return displays.contains { $0.id == id }
                ? .fullScreen(displayName: channel.targetDisplayName)
                : .displayMissing(displayName: channel.targetDisplayName)
        }
    }

    /// Displays that can take this output full screen: not the operator's, and not one the other output
    /// already fills.
    func fullScreenCandidates(_ role: OutputRole) -> [DisplayInfo] {
        let operatorID = operatorDisplayID ?? displays.first(where: \.isPrimary)?.id
        let taken = OutputRole.allCases.filter { $0 != role }.compactMap { other -> CGDirectDisplayID? in
            guard let channel = channels[other], channel.isEnabled, case .display(let id) = channel.target else { return nil }
            return id
        }
        return displays.filter { $0.id != operatorID && !taken.contains($0.id) }
    }

    func show(_ target: OutputTarget, for role: OutputRole = .audience) {
        var channel = channels[role] ?? Channel()
        if case .display(let id) = target, let display = displays.first(where: { $0.id == id }) {
            channel.targetDisplayName = display.name
        }
        channel.target = target
        channel.isEnabled = true
        channels[role] = channel
        apply(role)
    }

    func hide(_ role: OutputRole = .audience) {
        channels[role]?.isEnabled = false
        apply(role)
    }

    func hideAll() {
        for role in OutputRole.allCases { hide(role) }
    }

    func toggle(_ role: OutputRole = .audience) {
        isEnabled(role) ? hide(role) : show(target(role), for: role)
    }

    func operatorWindowMoved(to screen: NSScreen?) {
        operatorDisplayID = screen.flatMap(DisplayDiscovery.displayID(of:))
    }

    private func screensChanged() {
        displays = DisplayDiscovery.currentDisplays()
        Log.output.info("Displays changed: \(self.displays.map(\.name), privacy: .public)")
        for role in OutputRole.allCases { apply(role) }
    }

    private func apply(_ role: OutputRole) {
        guard let controller = controllers[role], let channel = channels[role] else { return }
        guard channel.isEnabled else {
            controller.hide()
            return
        }
        switch channel.target {
        case .windowed:
            controller.showWindowed()
        case .display(let id):
            if let screen = DisplayDiscovery.screen(for: id) {
                controller.showFullScreen(on: screen, displayID: id)
            } else {
                controller.hide()
                Log.output.error("\(role.title, privacy: .public) display \(channel.targetDisplayName, privacy: .public) is not connected")
            }
        }
    }
}
