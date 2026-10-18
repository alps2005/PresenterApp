import SwiftUI
import PresenterCore

extension PresenterCore.SlideTransition.Kind {
    var title: String {
        switch self {
        case .dissolve: "Dissolve"
        case .fadeThroughBlack: "Fade Through Black"
        case .push: "Push"
        case .wipe: "Wipe"
        case .zoom: "Zoom"
        }
    }
}

extension ElementTransition.Kind {
    var title: String {
        switch self {
        case .fade: "Fade"
        case .push: "Push"
        case .wipe: "Wipe"
        case .zoom: "Zoom"
        }
    }
}

/// Four arrows for the side a Push or Wipe comes in from (or an element's Out leaves through). Each arrow points
/// the way the content moves.
struct TransitionEdgePicker: View {
    @Binding var edge: TransitionEdge
    var phase: ElementPhase = .in

    var body: some View {
        Picker("Direction", selection: $edge) {
            ForEach(TransitionEdge.allCases, id: \.self) { edge in
                Image(systemName: arrow(for: edge))
                    .accessibilityLabel(label(for: edge))
                    .help(label(for: edge))
                    .tag(edge)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func arrow(for edge: TransitionEdge) -> String {
        // Coming in from the left moves right; leaving through the left moves left.
        let opposite: TransitionEdge = switch edge {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
        let movesTowards = phase == .out ? edge : opposite
        return switch movesTowards {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .top: "arrow.up"
        case .bottom: "arrow.down"
        }
    }

    private func label(for edge: TransitionEdge) -> String {
        let side = switch edge {
        case .left: "left"
        case .right: "right"
        case .top: "top"
        case .bottom: "bottom"
        }
        return phase == .out ? "Out through the \(side)" : "In from the \(side)"
    }
}

/// Under a thumbnail: the slide has elements with their own transitions.
struct ElementTransitionsMark: View {
    var body: some View {
        Image(systemName: "sparkles")
            .foregroundStyle(.secondary)
            .help("Some of this slide's elements have their own transitions")
            .accessibilityLabel("Has element transitions")
    }
}
