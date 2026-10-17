import SwiftUI
import PresenterCore

/// Font, colour, alignment and position of the cued slide's text. `slide` should be the slide as drawn (themed), so
/// the controls show the look the operator sees.
struct TextStyleInspector: View {
    let coordinator: PresentationCoordinator
    let slide: SlideDocument
    let presentationID: UUID
    @State private var isConfirmingApplyToAll = false

    private var element: TextElement {
        slide.primaryTextElement ?? TextElement(text: "")
    }

    private var style: TextStyle { element.style }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
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

    private var positionControls: some View {
        TextPositionControls(box: element.box, alignment: style.alignment) { box, alignment in
            coordinator.setTextBox(box, slideID: slide.id, inPresentation: presentationID)
            if style.alignment != alignment {
                var updated = style
                updated.alignment = alignment
                coordinator.setTextStyle(updated, slideID: slide.id, inPresentation: presentationID)
            }
        }
    }
}
