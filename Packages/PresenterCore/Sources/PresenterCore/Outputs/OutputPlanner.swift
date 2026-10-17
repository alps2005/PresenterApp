import CoreGraphics
import Foundation

/// A connected display. `id` is the CoreGraphics display ID: stable while the display stays connected, but not
/// guaranteed across launches; persisting the selected display needs a durable identity.
public struct DisplayInfo: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let frame: CGRect
    /// The display with the menu bar.
    public let isPrimary: Bool

    public init(id: UInt32, name: String, frame: CGRect, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
    }

    public var resolutionDescription: String {
        "\(Int(frame.width))×\(Int(frame.height))"
    }
}

public enum OutputTarget: Hashable, Sendable {
    case windowed
    case display(UInt32)
}

public enum OutputStatus: Equatable, Sendable {
    case off
    case windowed
    case fullScreen(displayName: String)
    /// The chosen display is gone. Output is hidden and comes back if the display reconnects.
    case displayMissing(displayName: String)
}

/// Which output a command is for. The stage display never shows audience content controls, and the audience
/// never sees stage-only information.
public enum OutputRole: CaseIterable, Hashable, Sendable {
    case audience
    case stage

    public var title: String {
        switch self {
        case .audience: "Audience Output"
        case .stage: "Stage Display"
        }
    }
}

/// Where an output's window should be right now.
public enum OutputPlacement: Equatable, Sendable {
    case hidden
    case windowed
    case fullScreen(displayID: UInt32)
}

/// Decides where the audience and stage outputs go, from the connected displays and the operator's choices.
/// UI-free: the app reports displays and commands, then places each output's window as `placement(_:)` says.
public struct OutputPlanner: Equatable, Sendable {
    private struct Channel: Equatable, Sendable {
        var target: OutputTarget = .windowed
        /// The operator's intent. The window may still be hidden if the chosen display is missing.
        var isEnabled = false
        var targetDisplayName = ""
    }

    public var displays: [DisplayInfo]
    /// The display showing the operator window. Full-screen output is never offered there.
    public var operatorDisplayID: UInt32?
    private var channels: [OutputRole: Channel] = [.audience: Channel(), .stage: Channel()]

    public init(displays: [DisplayInfo] = [], operatorDisplayID: UInt32? = nil) {
        self.displays = displays
        self.operatorDisplayID = operatorDisplayID
    }

    public func isEnabled(_ role: OutputRole) -> Bool { channels[role]?.isEnabled ?? false }
    public func target(_ role: OutputRole) -> OutputTarget { channels[role]?.target ?? .windowed }

    public func status(_ role: OutputRole) -> OutputStatus {
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

    /// Where the output's window goes. A missing display hides it; it returns when the display reconnects.
    public func placement(_ role: OutputRole) -> OutputPlacement {
        switch status(role) {
        case .off, .displayMissing: .hidden
        case .windowed: .windowed
        case .fullScreen: if case .display(let id) = target(role) { .fullScreen(displayID: id) } else { .hidden }
        }
    }

    /// Displays that can take this output full screen: not the operator's, and not one the other output
    /// already fills.
    public func fullScreenCandidates(_ role: OutputRole) -> [DisplayInfo] {
        let operatorID = operatorDisplayID ?? displays.first { $0.isPrimary }?.id
        let taken = takenDisplays(otherThan: role)
        return displays.filter { $0.id != operatorID && !taken.contains($0.id) }
    }

    /// Connected displays the other output fills, so the menu can say why they aren't offered for this one.
    public func displaysInUse(byOtherThan role: OutputRole) -> [DisplayInfo] {
        let taken = takenDisplays(otherThan: role)
        return displays.filter { taken.contains($0.id) }
    }

    /// Turns the output on at `target`. Returns false, changing nothing, if the other output already fills
    /// that display: two outputs never share a screen.
    @discardableResult
    public mutating func show(_ target: OutputTarget, for role: OutputRole) -> Bool {
        if case .display(let id) = target, takenDisplays(otherThan: role).contains(id) { return false }
        var channel = channels[role] ?? Channel()
        if case .display(let id) = target, let display = displays.first(where: { $0.id == id }) {
            channel.targetDisplayName = display.name
        }
        channel.target = target
        channel.isEnabled = true
        channels[role] = channel
        return true
    }

    /// Turns the output off, keeping its target for next time. Also used when the operator closes its window.
    public mutating func hide(_ role: OutputRole) {
        channels[role]?.isEnabled = false
    }

    @discardableResult
    public mutating func toggle(_ role: OutputRole) -> Bool {
        if isEnabled(role) {
            hide(role)
            return true
        }
        return show(target(role), for: role)
    }

    private func takenDisplays(otherThan role: OutputRole) -> [UInt32] {
        OutputRole.allCases.filter { $0 != role }.compactMap { other in
            guard let channel = channels[other], channel.isEnabled, case .display(let id) = channel.target else { return nil }
            return id
        }
    }
}
