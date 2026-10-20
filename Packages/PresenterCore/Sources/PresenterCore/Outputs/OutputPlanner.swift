import CoreGraphics
import Foundation

/// What identifies a display across launches and reconnections, unlike its CoreGraphics ID. Zero means the display
/// didn't report that number.
public struct DisplayIdentity: Codable, Hashable, Sendable {
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var name: String

    public init(vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0, name: String) {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.name = name
    }

    /// The connected display this one is, if it can tell: the same serial number, else the only display of the same
    /// make, model and name, else the only display with the same name.
    public func match(in displays: [DisplayInfo]) -> DisplayInfo? {
        if serial != 0, let same = displays.first(where: {
            $0.identity.vendor == vendor && $0.identity.model == model && $0.identity.serial == serial
        }) {
            return same
        }
        if vendor != 0 || model != 0 {
            let sameModel = displays.filter { $0.identity.vendor == vendor && $0.identity.model == model && $0.name == name }
            if sameModel.count == 1 { return sameModel[0] }
        }
        let sameName = displays.filter { $0.name == name }
        return sameName.count == 1 ? sameName[0] : nil
    }
}

/// A connected display. `id` is the CoreGraphics display ID: stable while the display stays connected, but not
/// guaranteed across launches or reconnections, so remembered displays are found by `identity`.
public struct DisplayInfo: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let frame: CGRect
    /// The display with the menu bar.
    public let isPrimary: Bool
    public let identity: DisplayIdentity

    public init(id: UInt32, name: String, frame: CGRect, isPrimary: Bool, identity: DisplayIdentity? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.isPrimary = isPrimary
        self.identity = identity ?? DisplayIdentity(name: name)
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
    /// The chosen display is connected but has the operator window. Output is hidden and fills the display once the
    /// operator window moves to another screen.
    case displayHasOperatorWindow(displayName: String)
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

/// Where an output went last time, kept on this Mac so the outputs come back on the same screens at launch.
public struct SavedOutput: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// The full-screen display. Nil means in a window.
    public var display: DisplayIdentity?

    public init(isEnabled: Bool, display: DisplayIdentity? = nil) {
        self.isEnabled = isEnabled
        self.display = display
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
        /// The full-screen display, to find it again when it reconnects with a different ID.
        var targetIdentity: DisplayIdentity?
    }

    /// CoreGraphics ID for a remembered display that isn't connected: kCGNullDirectDisplay, never a real one.
    private static let notConnected: UInt32 = 0

    public var displays: [DisplayInfo] {
        didSet { findRememberedDisplays() }
    }
    /// The display showing the operator window. Full-screen output is never offered there.
    public var operatorDisplayID: UInt32? {
        didSet { findRememberedDisplays() }
    }
    private var channels: [OutputRole: Channel] = [.audience: Channel(), .stage: Channel()]

    public init(displays: [DisplayInfo] = [], operatorDisplayID: UInt32? = nil) {
        self.displays = displays
        self.operatorDisplayID = operatorDisplayID
    }

    /// What to remember about the output: whether it's on, and its full-screen display.
    public func saved(_ role: OutputRole) -> SavedOutput {
        let channel = channels[role] ?? Channel()
        guard case .display = channel.target else { return SavedOutput(isEnabled: channel.isEnabled) }
        return SavedOutput(isEnabled: channel.isEnabled, display: channel.targetIdentity)
    }

    /// Puts the output back where it was. A remembered display that isn't connected (or that the operator window or
    /// the other output is on) leaves the output waiting for it, hidden, as when a display is unplugged mid-service.
    public mutating func restore(_ saved: SavedOutput, for role: OutputRole) {
        var channel = Channel()
        if let identity = saved.display {
            let display = identity.match(in: displays)
            let usable = display.map { candidate in fullScreenCandidates(role).contains { $0.id == candidate.id } } ?? false
            channel.target = .display(usable ? display!.id : Self.notConnected)
            channel.targetDisplayName = display?.name ?? identity.name
            channel.targetIdentity = identity
        }
        channel.isEnabled = saved.isEnabled
        channels[role] = channel
    }

    public func isEnabled(_ role: OutputRole) -> Bool { channels[role]?.isEnabled ?? false }
    public func target(_ role: OutputRole) -> OutputTarget { channels[role]?.target ?? .windowed }

    public func status(_ role: OutputRole) -> OutputStatus {
        guard let channel = channels[role], channel.isEnabled else { return .off }
        switch channel.target {
        case .windowed:
            return .windowed
        case .display(let id):
            if displays.contains(where: { $0.id == id }) { return .fullScreen(displayName: channel.targetDisplayName) }
            if let display = channel.targetIdentity?.match(in: displays), display.id == operatorScreenID {
                return .displayHasOperatorWindow(displayName: display.name)
            }
            return .displayMissing(displayName: channel.targetDisplayName)
        }
    }

    /// Where the output's window goes. A missing display hides it; it returns when the display reconnects.
    public func placement(_ role: OutputRole) -> OutputPlacement {
        switch status(role) {
        case .off, .displayMissing, .displayHasOperatorWindow: .hidden
        case .windowed: .windowed
        case .fullScreen: if case .display(let id) = target(role) { .fullScreen(displayID: id) } else { .hidden }
        }
    }

    /// Displays that can take this output full screen: not the operator's, and not one the other output
    /// already fills.
    public func fullScreenCandidates(_ role: OutputRole) -> [DisplayInfo] {
        let taken = takenDisplays(otherThan: role)
        return displays.filter { $0.id != operatorScreenID && !taken.contains($0.id) }
    }

    /// The operator window's display, or the menu bar's until the window reports one.
    private var operatorScreenID: UInt32? {
        operatorDisplayID ?? displays.first { $0.isPrimary }?.id
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
            channel.targetIdentity = display.identity
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

    /// Points each output's remembered display at its current ID, after a display connects, comes back with a new ID,
    /// leaves its ID to another display, or stops having the operator window.
    private mutating func findRememberedDisplays() {
        for role in OutputRole.allCases {
            guard var channel = channels[role], case .display(let id) = channel.target, let identity = channel.targetIdentity else {
                continue
            }
            if let current = displays.first(where: { $0.id == id }), identity.match(in: [current]) != nil { continue }
            channel.target = .display(Self.notConnected)
            if let display = identity.match(in: displays), fullScreenCandidates(role).contains(where: { $0.id == display.id }) {
                channel.target = .display(display.id)
                channel.targetDisplayName = display.name
            }
            channels[role] = channel
        }
    }

    private func takenDisplays(otherThan role: OutputRole) -> [UInt32] {
        OutputRole.allCases.filter { $0 != role }.compactMap { other in
            guard let channel = channels[other], channel.isEnabled, case .display(let id) = channel.target else { return nil }
            return id
        }
    }
}
