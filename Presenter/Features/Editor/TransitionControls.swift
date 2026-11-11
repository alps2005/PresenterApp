import SwiftUI
import PresenterCore

extension PresenterCore.SlideTransition.Kind {
    var title: String {
        switch self {
        case .dissolve: String(localized: "Dissolve")
        case .fadeThroughBlack: String(localized: "Fade Through Black")
        case .push: String(localized: "Push")
        case .wipe: String(localized: "Wipe")
        case .zoom: String(localized: "Zoom")
        }
    }
}

extension ElementTransition.Kind {
    var title: String {
        switch self {
        case .fade: String(localized: "Fade")
        case .push: String(localized: "Push")
        case .wipe: String(localized: "Wipe")
        case .zoom: String(localized: "Zoom")
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
        // Whole sentences, so each language can word the direction its own way.
        switch (phase == .out, edge) {
        case (true, .left): String(localized: "Out through the left")
        case (true, .right): String(localized: "Out through the right")
        case (true, .top): String(localized: "Out through the top")
        case (true, .bottom): String(localized: "Out through the bottom")
        case (false, .left): String(localized: "In from the left")
        case (false, .right): String(localized: "In from the right")
        case (false, .top): String(localized: "In from the top")
        case (false, .bottom): String(localized: "In from the bottom")
        }
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
