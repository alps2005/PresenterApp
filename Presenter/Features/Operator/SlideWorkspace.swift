import SwiftUI
import PresenterCore

/// Slides of the selected playlist item. Click cues a slide; double-click takes it live.
/// With the grid focused: → or Space = next, ← = previous, Return = take cued slide live.
struct SlideWorkspace: View {
    let coordinator: PresentationCoordinator
    @FocusState private var isGridFocused: Bool
    @State private var slidePendingDeletion: SlideDocument?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]

    var body: some View {
        if let itemID = coordinator.state.selectedItemID,
           let presentation = coordinator.project.presentation(forItem: itemID) {
            VStack(spacing: 0) {
                header(presentation: presentation, itemID: itemID)
                Divider()
                grid(presentation: presentation, itemID: itemID)
                Divider()
                SlideTextEditor(coordinator: coordinator)
            }
            // AppKit otherwise gives first focus to the title field, so Space/arrows meant for
            // slide navigation would overwrite the presentation title. (`.defaultFocus` is not enough.)
            .task { isGridFocused = true }
            .confirmationDialog(
                "Delete this slide?",
                isPresented: Binding(
                    get: { slidePendingDeletion != nil },
                    set: { if !$0 { slidePendingDeletion = nil } }
                ),
                presenting: slidePendingDeletion
            ) { slide in
                Button("Delete", role: .destructive) {
                    coordinator.deleteSlide(slide.id, inPresentation: presentation.id)
                }
            } message: { _ in
                Text("If this slide is live, it stays on the audience output until you take another slide live.")
            }
        } else {
            ContentUnavailableView(
                "No Presentation Selected",
                systemImage: "rectangle.on.rectangle",
                description: Text("Select a playlist item, or create a new presentation.")
            )
        }
    }

    private func header(presentation: PresentationDocument, itemID: UUID) -> some View {
        HStack {
            TextField("Title", text: Binding(
                get: { presentation.title },
                set: { coordinator.renamePresentation(presentation.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.title2.bold())
            .onSubmit { isGridFocused = true }

            Button {
                coordinator.addSlide(toItem: itemID)
            } label: {
                Label("Add Slide", systemImage: "plus.rectangle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func grid(presentation: PresentationDocument, itemID: UUID) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(presentation.slides.enumerated()), id: \.element.id) { index, slide in
                    let position = SlidePosition(itemID: itemID, slideID: slide.id)
                    SlideThumbnail(
                        slide: presentation.rendered(slide),
                        number: index + 1,
                        isCued: coordinator.state.preview == position,
                        isLive: coordinator.state.live?.position == position
                    )
                    .onTapGesture {
                        isGridFocused = true
                        coordinator.cueSlide(slide.id, inItem: itemID)
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        coordinator.takeLive(slideID: slide.id, inItem: itemID)
                    })
                    .contextMenu {
                        Button("Take Live") {
                            coordinator.takeLive(slideID: slide.id, inItem: itemID)
                        }
                        Divider()
                        Button("Delete Slide…", role: .destructive) {
                            slidePendingDeletion = slide
                        }
                    }
                }
            }
            .padding(16)
        }
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { coordinator.nextSlide(); return .handled }
        .onKeyPress(.space) { coordinator.nextSlide(); return .handled }
        .onKeyPress(.leftArrow) { coordinator.previousSlide(); return .handled }
        .onKeyPress(.return) { coordinator.takeLive(); return .handled }
    }
}

struct SlideThumbnail: View {
    let slide: RenderedSlide
    let number: Int
    let isCued: Bool
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SlideRenderView(scene: .slide(slide))
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(borderColor, lineWidth: isLive || isCued ? 3 : 1)
                }
            HStack(spacing: 6) {
                Text("\(number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if isCued { StateBadge(text: "CUED", color: .accentColor) }
                if isLive { StateBadge(text: "LIVE", color: .red) }
            }
            .font(.caption)
        }
        .contentShape(Rectangle())
    }

    private var borderColor: Color {
        if isLive { return .red }
        if isCued { return .accentColor }
        return .secondary.opacity(0.4)
    }
}

struct StateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}
