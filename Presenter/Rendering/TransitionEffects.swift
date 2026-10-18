import SwiftUI
import PresenterCore

/// When the slide being drawn arrived on (or left) the audience output, so its elements can play their own
/// transitions. Only the audience output and its preview set it; thumbnails and the editor draw slides still.
struct ElementClock: Equatable {
    let phase: ElementPhase
    let start: Date
    /// On a slide leaving without a slide transition, elements without their own Out transition are already gone.
    var hidesStill = false
}

private struct ElementClockKey: EnvironmentKey {
    static let defaultValue: ElementClock? = nil
}

extension EnvironmentValues {
    var elementClock: ElementClock? {
        get { self[ElementClockKey.self] }
        set { self[ElementClockKey.self] = newValue }
    }
}

extension View {
    /// Applies one moment of a transition (see `TransitionMath`). Offsets are fractions of `canvas`. `wipes` adds the
    /// mask a Wipe needs; it's decided per transition, not per frame, so the view's identity never changes mid-way.
    @ViewBuilder
    func transitionFrame(_ frame: TransitionFrame, canvas: CGSize, wipes: Bool) -> some View {
        let moved = self
        if wipes {
            moved
                .mask { RevealMask(fraction: frame.reveal, edge: frame.revealEdge) }
                .scaleEffect(frame.scale)
                .opacity(frame.opacity)
                .offset(x: frame.offsetX * canvas.width, y: frame.offsetY * canvas.height)
        } else {
            moved
                .scaleEffect(frame.scale)
                .opacity(frame.opacity)
                .offset(x: frame.offsetX * canvas.width, y: frame.offsetY * canvas.height)
        }
    }
}

/// The part of a view a Wipe shows: `fraction` of it, starting from `edge`.
private struct RevealMask: View {
    let fraction: Double
    let edge: TransitionEdge

    var body: some View {
        let horizontal = edge == .left || edge == .right
        Rectangle()
            .scaleEffect(x: horizontal ? fraction : 1, y: horizontal ? 1 : fraction, anchor: anchor)
    }

    private var anchor: UnitPoint {
        switch edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }
}

/// A slide layer partway through a slide transition. Animatable, so one animated `progress` drives every effect.
struct SlideTransitionEffect: ViewModifier, Animatable {
    var progress: Double
    let transition: PresenterCore.SlideTransition?
    let role: TransitionMath.Role
    /// False for the slide's see-through words and elements; see `TransitionMath.frame(for:role:progress:opaque:)`.
    let opaque: Bool
    let canvas: CGSize

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let frame = transition.map { TransitionMath.frame(for: $0, role: role, progress: progress, opaque: opaque) } ?? .identity
        content.transitionFrame(frame, canvas: canvas, wipes: transition?.kind == .wipe && (role == .incoming || !opaque))
    }
}
