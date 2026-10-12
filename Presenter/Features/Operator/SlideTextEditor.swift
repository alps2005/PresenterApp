import SwiftUI
import PresenterCore

/// Edits the cued slide's text. Edits change the project only; the audience output updates
/// when the operator takes the slide live again.
struct SlideTextEditor: View {
    let coordinator: PresentationCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cued Slide Text")
                .font(.headline)

            if let preview = coordinator.state.preview,
               let presentation = coordinator.project.presentation(forItem: preview.itemID),
               let slide = presentation.slide(withID: preview.slideID) {
                TextEditor(text: Binding(
                    get: { slide.primaryText },
                    set: { coordinator.updateSlideText($0, slideID: slide.id, inPresentation: presentation.id) }
                ))
                .font(.body)
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Click a slide to cue and edit it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            }
        }
        .padding(12)
    }
}
