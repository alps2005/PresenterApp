import Foundation

/// The side of the canvas a Push or Wipe comes in from (or, for an element's Out transition, leaves through).
public enum TransitionEdge: String, Codable, Hashable, Sendable, CaseIterable {
    case left
    case right
    case top
    case bottom

    var opposite: TransitionEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// Points from the centre towards this edge, in fractions of the canvas (y grows downwards).
    var direction: (x: Double, y: Double) {
        switch self {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .top: (0, -1)
        case .bottom: (0, 1)
        }
    }
}

/// When an element transition plays: as its slide arrives, or as its slide leaves.
public enum ElementPhase: String, Codable, Hashable, Sendable {
    case `in`
    case out
}

/// A transition on one element of a slide (text, shape or image), for when the whole slide shouldn't transition.
/// It plays when the slide changes: In as the slide arrives, Out as it leaves.
public struct ElementTransition: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case fade
        /// Moves in from (or out through) `edge`.
        case push
        /// Revealed from (or hidden towards) `edge`.
        case wipe
        /// Grows in from smaller while fading in (or the reverse).
        case zoom
    }

    public var kind: Kind
    /// Used by Push and Wipe.
    public var edge: TransitionEdge
    public var duration: Double
    /// How long after the slide arrives an In transition starts. Out transitions start as the slide leaves.
    public var delay: Double

    public static let durationRange: ClosedRange<Double> = 0.2...2
    public static let delayRange: ClosedRange<Double> = 0...10

    public init(kind: Kind, edge: TransitionEdge = .left, duration: Double = 0.6, delay: Double = 0) {
        self.kind = kind
        self.edge = edge
        self.duration = duration
        self.delay = delay
    }

    /// How far the transition has run, from 0 to 1, `elapsed` seconds after the slide arrived (In) or left (Out).
    public func progress(elapsed: Double, phase: ElementPhase) -> Double {
        let start = phase == .in ? delay : 0
        guard duration > 0 else { return elapsed >= start ? 1 : 0 }
        return min(max((elapsed - start) / duration, 0), 1)
    }

    /// When the transition is over, in seconds after the slide arrived (In) or left (Out).
    public func end(phase: ElementPhase) -> Double {
        (phase == .in ? delay : 0) + duration
    }
}

/// How a transition shows a layer or element at one moment.
public struct TransitionFrame: Equatable, Sendable {
    public var opacity: Double = 1
    /// Offset in fractions of the canvas: x of its width, y of its height.
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var scale: Double = 1
    /// How much of the view shows, revealed starting from `revealEdge`. 1 shows all of it.
    public var reveal: Double = 1
    public var revealEdge: TransitionEdge = .left

    public static let identity = TransitionFrame()

    public init(opacity: Double = 1, offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1,
                reveal: Double = 1, revealEdge: TransitionEdge = .left) {
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.reveal = reveal
        self.revealEdge = revealEdge
    }
}

/// The geometry of every transition, as pure functions of progress, so the renderer only applies the result.
public enum TransitionMath {
    public enum Role: Sendable {
        /// The slide arriving.
        case incoming
        /// The slide it replaces.
        case outgoing
    }

    /// A slide layer `progress` (0...1) of the way through `transition`. An `opaque` layer (the background) hides
    /// whatever is under it, so the outgoing one can simply stay put underneath. A see-through layer (the slide's
    /// words and elements) can't, so its outgoing copy fades or is wiped away as the incoming one arrives.
    public static func frame(for transition: SlideTransition, role: Role, progress: Double, opaque: Bool = true) -> TransitionFrame {
        let p = min(max(progress, 0), 1)
        let outgoingFades = opaque ? TransitionFrame.identity : TransitionFrame(opacity: 1 - p)
        switch transition {
        case .dissolve:
            return role == .incoming ? TransitionFrame(opacity: p) : outgoingFades
        case .fadeThroughBlack:
            // Out over the first half, in over the second, so the middle is black.
            return role == .incoming ? TransitionFrame(opacity: max(0, 2 * p - 1)) : TransitionFrame(opacity: max(0, 1 - 2 * p))
        case .push(let edge, _):
            let d = edge.direction
            return role == .incoming
                ? TransitionFrame(offsetX: d.x * (1 - p), offsetY: d.y * (1 - p))
                : TransitionFrame(offsetX: -d.x * p, offsetY: -d.y * p)
        case .wipe(let edge, _):
            if role == .incoming { return TransitionFrame(reveal: p, revealEdge: edge) }
            // What's left of the outgoing slide is the part the line hasn't reached yet.
            return opaque ? .identity : TransitionFrame(reveal: 1 - p, revealEdge: edge.opposite)
        case .zoom:
            return role == .incoming ? TransitionFrame(opacity: p, scale: 0.85 + 0.15 * p) : outgoingFades
        }
    }

    /// An element `progress` (0...1) of the way through its In or Out transition.
    public static func frame(for transition: ElementTransition, phase: ElementPhase, progress: Double) -> TransitionFrame {
        // How much of the element shows: rising for In, falling for Out.
        let shown = phase == .in ? min(max(progress, 0), 1) : 1 - min(max(progress, 0), 1)
        switch transition.kind {
        case .fade:
            return TransitionFrame(opacity: shown)
        case .push:
            // A whole canvas away is always off screen, wherever the element sits.
            let d = transition.edge.direction
            return TransitionFrame(offsetX: d.x * (1 - shown), offsetY: d.y * (1 - shown))
        case .wipe:
            return TransitionFrame(reveal: shown, revealEdge: transition.edge)
        case .zoom:
            return TransitionFrame(opacity: shown, scale: 0.6 + 0.4 * shown)
        }
    }
}

extension SlideDocument {
    /// True when any element has its own transition.
    public var hasElementTransitions: Bool {
        elements.contains { $0[transition: .in] != nil || $0[transition: .out] != nil }
    }

    /// When the last of the elements' In or Out transitions is over, in seconds. 0 when none has one.
    public func elementTransitionsEnd(_ phase: ElementPhase) -> Double {
        elements.compactMap { $0[transition: phase]?.end(phase: phase) }.max() ?? 0
    }
}
