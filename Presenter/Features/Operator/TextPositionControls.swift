import SwiftUI
import PresenterCore

/// A 3×3 grid that pins text to an edge or corner of the slide, a margin slider, and Reset Position. Used by
/// Quick Edit and the theme editor.
struct TextPositionControls: View {
    /// Where the text is now. Nil is the centred flow layout.
    let box: TextBox?
    let alignment: HorizontalTextAlignment
    /// Places the text: the new box (nil for the centred flow layout) and the alignment that goes with it.
    let onPlace: (TextBox?, HorizontalTextAlignment) -> Void

    private static let marginRange: ClosedRange<Double> = 0...0.3

    /// The anchor the text is pinned to, or nil for the default centred flow layout.
    private var anchor: BoxAnchor? {
        guard let box else { return nil }
        return BoxAnchor.allCases.first { $0.vertical == box.verticalAlignment && $0.horizontal == alignment }
    }

    private var margin: Double {
        box?.frame.y ?? 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Position").foregroundStyle(.secondary)
            Grid(horizontalSpacing: Spacing.xxs, verticalSpacing: Spacing.xxs) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { column in
                            anchorButton(BoxAnchor.allCases[row * 3 + column])
                        }
                    }
                }
            }
            HStack(spacing: Spacing.xs) {
                Text("Margin").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { margin },
                    set: { place(at: anchor ?? .center, margin: $0) }
                ), in: Self.marginRange)
                .frame(width: 90)
            }
            .disabled(box == nil)
            Button("Reset Position") { onPlace(nil, alignment) }
                .disabled(box == nil)
        }
    }

    private func anchorButton(_ anchor: BoxAnchor) -> some View {
        let isSelected = self.anchor == anchor
        return Button {
            place(at: anchor, margin: margin)
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 22, height: 14)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Place text \(anchor.label.lowercased())"))
        .accessibilityLabel("Position \(anchor.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func place(at anchor: BoxAnchor, margin: Double) {
        onPlace(.preset(anchor, margin: margin), anchor.horizontal)
    }
}

private extension BoxAnchor {
    var label: String {
        switch self {
        case .topLeading: String(localized: "Top Left")
        case .top: String(localized: "Top")
        case .topTrailing: String(localized: "Top Right")
        case .leading: String(localized: "Left")
        case .center: String(localized: "Center")
        case .trailing: String(localized: "Right")
        case .bottomLeading: String(localized: "Bottom Left")
        case .bottom: String(localized: "Bottom")
        case .bottomTrailing: String(localized: "Bottom Right")
        }
    }
}
