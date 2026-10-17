import SwiftUI
import PresenterCore

/// Edit a presentation's words as one document, like ProPresenter's Reflow editor. Changes apply as you type.
/// Slides keep their look; a blank line starts a new slide and a section name (Verse 1, Coro…) labels them.
struct ReflowSheet: View {
    let coordinator: PresentationCoordinator
    let presentationID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var presentation: PresentationDocument? {
        coordinator.project.presentation(withID: presentationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Reflow · \(presentation?.title ?? "")").font(.title2.bold())
                Spacer()
                Text(presentation.map { $0.slides.count == 1 ? "1 slide" : "\($0.slides.count) slides" } ?? "")
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: Spacing.lg) {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.sm)
                    .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: Radius.card))
                    .frame(minWidth: 360, minHeight: 420)
                    .onChange(of: text) { _, newText in
                        coordinator.reflow(newText, presentationID: presentationID)
                    }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
                        if let presentation {
                            ForEach(Array(presentation.slides.enumerated()), id: \.element.id) { index, slide in
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    SlideRenderView(scene: .slide(presentation.rendered(slide)))
                                        .aspectRatio(16 / 9, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.badge))
                                    HStack(spacing: Spacing.xs) {
                                        Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                                        if let label = slide.label { GroupLabelTag(label: label) }
                                    }
                                    .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .frame(width: 340)
            }

            Text("A blank line starts a new slide. A line with only a section name (Verse 1, Chorus, Coro, Puente…) labels the slides after it. \(LyricsParser.blankSlideMarker) keeps a slide without words. Slides keep their style; new ones copy the slide before them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Changes apply as you type. ⌘Z undoes them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 780)
        .onAppear { text = presentation?.reflowText ?? "" }
    }
}
