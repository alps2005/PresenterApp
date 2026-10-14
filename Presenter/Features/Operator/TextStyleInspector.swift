import SwiftUI
import PresenterCore

/// Font, colour, alignment and position of the cued slide's text.
struct TextStyleInspector: View {
    let coordinator: PresentationCoordinator
    let slide: SlideDocument
    let presentationID: UUID
    @State private var isConfirmingApplyToAll = false

    private static let marginRange: ClosedRange<Double> = 0...0.3

    private var element: TextElement {
        slide.primaryTextElement ?? TextElement(text: "")
    }

    private var style: TextStyle { element.style }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                TextStyleControls(style: Binding(
                    get: { style },
                    set: { coordinator.setTextStyle($0, slideID: slide.id, inPresentation: presentationID) }
                ))
                Button("Apply to All Slides…") { isConfirmingApplyToAll = true }
                    .help("Copy this slide's text style and position to every slide in the presentation")
            }

            positionControls
        }
        .controlSize(.small)
        .confirmationDialog("Apply this text style and position to every slide?", isPresented: $isConfirmingApplyToAll) {
            Button("Apply to All Slides") {
                coordinator.applyTextFormatToAllSlides(from: slide.id, inPresentation: presentationID)
            }
        } message: {
            Text("The text on each slide stays the same.")
        }
    }

    // MARK: Position

    /// The anchor the text is pinned to, or nil for the default centred flow layout.
    private var anchor: BoxAnchor? {
        guard let box = element.box else { return nil }
        return BoxAnchor.allCases.first { $0.vertical == box.verticalAlignment && $0.horizontal == style.alignment }
    }

    private var margin: Double {
        element.box?.frame.y ?? 0.1
    }

    private var positionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Position").foregroundStyle(.secondary)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { column in
                            anchorButton(BoxAnchor.allCases[row * 3 + column])
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Margin").foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { margin },
                    set: { place(at: anchor ?? .center, margin: $0) }
                ), in: Self.marginRange)
                .frame(width: 90)
            }
            .disabled(element.box == nil)
            Button("Reset Position") {
                coordinator.setTextBox(nil, slideID: slide.id, inPresentation: presentationID)
            }
            .disabled(element.box == nil)
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
        .help("Place text \(anchor.label.lowercased())")
        .accessibilityLabel("Position \(anchor.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func place(at anchor: BoxAnchor, margin: Double) {
        coordinator.setTextBox(.preset(anchor, margin: margin), slideID: slide.id, inPresentation: presentationID)
        if style.alignment != anchor.horizontal {
            var updated = style
            updated.alignment = anchor.horizontal
            coordinator.setTextStyle(updated, slideID: slide.id, inPresentation: presentationID)
        }
    }
}

private extension BoxAnchor {
    var label: String {
        switch self {
        case .topLeading: "Top Left"
        case .top: "Top"
        case .topTrailing: "Top Right"
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        case .bottomLeading: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom Right"
        }
    }
}
