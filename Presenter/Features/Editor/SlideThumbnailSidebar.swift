import SwiftUI
import PresenterCore

/// The slide editor's left column: numbered thumbnails to select and drag into a new order.
struct SlideThumbnailSidebar: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument
    /// Nil for the props library, which has no playlist entry.
    let itemID: UUID?
    @Binding var selection: UUID?
    let onAddSlide: () -> Void
    @State private var slidePendingDeletion: SlideDocument?

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(presentation.slides.enumerated()), id: \.element.id) { index, slide in
                row(index: index, slide: slide)
                    .tag(slide.id)
                    .contextMenu {
                        if let itemID {
                            Button("Take Live") {
                                coordinator.takeLive(slideID: slide.id, inItem: itemID)
                            }
                            Divider()
                        }
                        Button("Delete Slide…", role: .destructive) {
                            slidePendingDeletion = slide
                        }
                    }
            }
            .onMove { coordinator.moveSlides(inPresentation: presentation.id, fromOffsets: $0, toOffset: $1) }
        }
        .solidSidebar()
        .hardScrollEdges()
        .safeAreaInset(edge: .bottom) {
            Button { onAddSlide() } label: {
                Label("Add Slide", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmSlideDeletion(of: $slidePendingDeletion) { slide in
            coordinator.deleteSlide(slide.id, inPresentation: presentation.id)
        }
    }

    private func row(index: Int, slide: SlideDocument) -> some View {
        let position = itemID.map { SlidePosition(itemID: $0, slideID: slide.id) }
        let isLive = position != nil && coordinator.state.live?.position == position
        let isCued = position != nil && coordinator.state.preview == position
        return HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(index + 1)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                SlideRenderView(scene: .slide(coordinator.project.rendered(slide, in: presentation)))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .tileFrame(TileState(isLive: isLive, isCued: isCued), cornerRadius: Radius.badge)
                if isLive || isCued || slide.label != nil || slide.hasElementTransitions || slide.audioCue != nil {
                    HStack(spacing: Spacing.xs) {
                        if let label = slide.label { GroupLabelTag(label: label) }
                        Spacer(minLength: 0)
                        if slide.hasElementTransitions { ElementTransitionsMark() }
                        if let cue = slide.audioCue { AudioCueMark(cue: cue) }
                        if isCued { StateBadge(.cued) }
                        if isLive { StateBadge(.live) }
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
