import AppKit
import os
import Observation
import PresenterCore
import SwiftUI

/// Tracks connected displays and places the two audience outputs and the stage display as `OutputPlanner` decides.
/// Remembers where each output was and each audience output's look, on this Mac, and puts them back at launch.
@Observable
final class OutputManager {
    private(set) var planner = OutputPlanner(displays: DisplayDiscovery.currentDisplays())
    /// What each audience output shows. Missing means everything.
    private(set) var looks: [OutputRole: OutputLook] = [:]

    @ObservationIgnored private var controllers: [OutputRole: OutputWindowController] = [:]
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults
    /// The saved outputs are put back once the operator window is on screen (see `operatorWindowMoved(to:)`).
    @ObservationIgnored private var hasRestored = false

    /// Per Mac, not in the project: a project opened on another Mac shouldn't reach for this one's screens.
    static let savedOutputsKey = "savedOutputs"
    static let looksKey = "outputLooks"

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary, playback: MediaPlaybackController,
         defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for role in OutputRole.allCases where role.isAudience {
            controllers[role] = OutputWindowController(title: role.title) { [weak self] in
                AnyView(
                    AudienceOutputView(coordinator: coordinator) { self?.look(role) ?? .everything }
                        .environment(mediaLibrary)
                        .environment(playback)
                        .environment(\.showsLiveVideo, true)
                )
            }
        }
        controllers[.stage] = OutputWindowController(title: OutputRole.stage.title) {
            AnyView(StageOutputView(coordinator: coordinator).environment(mediaLibrary))
        }
        for role in OutputRole.allCases {
            controllers[role]?.onUserClosedWindow = { [weak self] in
                self?.planner.hide(role)
                self?.save()
            }
        }
        if let data = defaults.data(forKey: Self.looksKey),
           let saved = try? JSONDecoder().decode([String: OutputLook].self, from: data) {
            for role in OutputRole.allCases { looks[role] = saved[role.storageKey] }
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
    /// Whether the audience output or stage display is on (or waiting for its screen): a service is under way.
    var isAnyOutputOn: Bool { OutputRole.allCases.contains { isEnabled($0) } }
    func target(_ role: OutputRole) -> OutputTarget { planner.target(role) }
    func status(_ role: OutputRole) -> OutputStatus { planner.status(role) }
    func fullScreenCandidates(_ role: OutputRole) -> [DisplayInfo] { planner.fullScreenCandidates(role) }
    func displaysInUse(byOtherThan role: OutputRole) -> [DisplayInfo] { planner.displaysInUse(byOtherThan: role) }

    /// The other output full screen on this display, to say which one has it.
    func role(otherThan role: OutputRole, on display: DisplayInfo) -> OutputRole? {
        OutputRole.allCases.first { $0 != role && isEnabled($0) && target($0) == .display(display.id) }
    }

    func look(_ role: OutputRole) -> OutputLook { looks[role] ?? .everything }

    func setLook(_ look: OutputLook, for role: OutputRole) {
        looks[role] = look
        let saved = Dictionary(uniqueKeysWithValues: looks.map { ($0.key.storageKey, $0.value) })
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.looksKey) }
    }

    func show(_ target: OutputTarget, for role: OutputRole = .audience) {
        planner.show(target, for: role)
        apply(role)
        save()
    }

    func hide(_ role: OutputRole = .audience) {
        planner.hide(role)
        apply(role)
        save()
    }

    /// Closes the output windows when the app quits, leaving what's remembered for the next launch.
    func hideAll() {
        for role in OutputRole.allCases {
            planner.hide(role)
            apply(role)
        }
    }

    func toggle(_ role: OutputRole = .audience) {
        planner.toggle(role)
        apply(role)
        save()
    }

    func operatorWindowMoved(to screen: NSScreen?) {
        let placements = OutputRole.allCases.map(planner.placement)
        planner.operatorDisplayID = screen.flatMap(DisplayDiscovery.displayID(of:))
        // Not before: SwiftUI opens the operator window at launch only if no other window is open, and the planner
        // needs to know the operator's screen so an output never covers it.
        guard hasRestored else {
            hasRestored = true
            restore()
            return
        }
        // An output waiting for the screen the operator window just left fills it now.
        for (role, placement) in zip(OutputRole.allCases, placements) where planner.placement(role) != placement {
            apply(role)
        }
    }

    // MARK: Remembering

    private func restore() {
        guard let data = defaults.data(forKey: Self.savedOutputsKey),
              let saved = try? JSONDecoder().decode([String: SavedOutput].self, from: data) else { return }
        for role in OutputRole.allCases {
            guard let output = saved[role.storageKey] else { continue }
            planner.restore(output, for: role)
            apply(role)
            Log.output.info("Restored \(role.title, privacy: .public): \(String(describing: self.planner.status(role)), privacy: .public)")
        }
    }

    private func save() {
        let saved = Dictionary(uniqueKeysWithValues: OutputRole.allCases.map { ($0.storageKey, planner.saved($0)) })
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.savedOutputsKey) }
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

private extension OutputRole {
    var storageKey: String {
        switch self {
        case .audience: "audience"
        case .secondAudience: "secondAudience"
        case .stage: "stage"
        }
    }
}
