import SwiftUI
import PresenterCore

/// Quick Edit: the cued slide's text, text style and position, and background, below the workspace.
/// Shown or hidden with the toolbar toggle (⌥⌘E). Edits change the project only; the audience output
/// updates when the operator takes the slide live again. The full editor is the Edit button.
struct SlideEditor: View {
    /// Fixed so switching tabs never resizes the slide grid above.
    static let contentHeight: CGFloat = 150

    private enum Tab: String, CaseIterable, Identifiable {
        case text = "Text"
        case style = "Style"
        case background = "Background"

        var id: Self { self }
    }

    let coordinator: PresentationCoordinator
    @State private var tab: Tab = .text

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Quick Edit · Cued Slide")
                    .font(.headline)
                Spacer()
                Picker("Editor", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Group {
                if let preview = coordinator.state.preview,
                   let presentation = coordinator.project.presentation(forItem: preview.itemID),
                   let slide = presentation.slide(withID: preview.slideID) {
                    switch tab {
                    case .text:
                        TextEditor(text: Binding(
                            get: { slide.primaryText },
                            set: { coordinator.updateSlideText($0, slideID: slide.id, inPresentation: presentation.id) }
                        ))
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.sm)
                        .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: Radius.card))
                    case .style:
                        TextStyleInspector(coordinator: coordinator, slide: slide, presentationID: presentation.id)
                    case .background:
                        BackgroundInspector(
                            coordinator: coordinator,
                            target: .slide(slide.id, presentationID: presentation.id)
                        )
                    }
                } else {
                    Text("Click a slide to cue and edit it.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(height: Self.contentHeight, alignment: .top)
        }
        .padding(Spacing.lg)
    }
}
