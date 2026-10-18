import SwiftUI
import PresenterCore

/// One library presentation's slides, shown in the workspace when it's clicked in the sidebar's Library.
/// For looking and editing only: slides go live from the show, so nothing here can be cued or taken live.
struct LibraryPresentationView: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument
    /// Setting it opens the slide editor on the presentation.
    @Binding var editSession: EditSession?
    /// Adds the presentation to the show and returns to it.
    let onAddToShow: () -> Void
    let onBackToShow: () -> Void
    @AppStorage("thumbnailWidth") private var thumbnailWidth = 180.0

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth * 1.45), spacing: Spacing.lg)]
    }

    private var title: String { presentation.title.isEmpty ? "Untitled" : presentation.title }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.lg) {
                    // In play order, like the show: the active arrangement's order, with repeats shown again.
                    ForEach(Array(presentation.arrangedSlides.enumerated()), id: \.element) { index, arranged in
                        if let slide = presentation.slide(withID: arranged.slideID) {
                            SlideThumbnail(
                                slide: coordinator.project.rendered(slide, in: presentation),
                                number: index + 1,
                                isCued: false,
                                isLive: false
                            )
                            .onTapGesture(count: 2) { edit(startingAt: slide.id) }
                            .contextMenu {
                                Button("Edit Slide") { edit(startingAt: slide.id) }
                            }
                            .help("Double-click to edit")
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .hardScrollEdges()
            .overlay {
                if presentation.slides.isEmpty {
                    ContentUnavailableView("No Slides", systemImage: "rectangle.on.rectangle")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Button { onBackToShow() } label: {
                    Label("Back to Show", systemImage: "chevron.left")
                }
                .help("Show the show's slides again")
                Button { onAddToShow() } label: {
                    Label("Add to Show", systemImage: "plus.circle")
                }
                .help("Add this presentation to the end of the show")
                Button { edit(startingAt: nil) } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Open this presentation in the slide editor")
            }
            Text("From the Library. Add it to the show to take it live.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.lg)
    }

    private func edit(startingAt slideID: UUID?) {
        editSession = EditSession(itemID: nil, presentationID: presentation.id, initialSlideID: slideID)
    }
}
