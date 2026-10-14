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
                            Button("Send to Live") {
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
        .safeAreaInset(edge: .bottom) {
            Button { onAddSlide() } label: {
                Label("Add Slide", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    }

    private func row(index: Int, slide: SlideDocument) -> some View {
        let position = itemID.map { SlidePosition(itemID: $0, slideID: slide.id) }
        let isLive = position != nil && coordinator.state.live?.position == position
        let isCued = position != nil && coordinator.state.preview == position
        return HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                SlideRenderView(scene: .slide(presentation.rendered(slide)))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLive ? Color.red : Color.secondary.opacity(0.4), lineWidth: isLive ? 2 : 1)
                    }
                if isLive || isCued || slide.label != nil {
                    HStack(spacing: 4) {
                        if let label = slide.label { GroupLabelTag(label: label) }
                        Spacer(minLength: 0)
                        if isCued { StateBadge(text: "CUED", color: .accentColor) }
                        if isLive { StateBadge(text: "LIVE", color: .red) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
