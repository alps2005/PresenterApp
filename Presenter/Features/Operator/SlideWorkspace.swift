import SwiftUI
import PresenterCore

/// Every playlist item's slides in one continuous scroll, in running order. The sidebar follows the
/// presentation at the top of the viewport; clicking a sidebar item scrolls to it.
/// Click cues a slide; double-click takes it live. With the workspace focused:
/// → or Space = next, ← = previous, Return = take cued slide live.
struct SlideWorkspace: View {
    let coordinator: PresentationCoordinator
    /// Set by the sidebar when the operator clicks an item; the workspace scrolls there and clears it.
    @Binding var scrollRequest: UUID?
    /// Setting it opens the slide editor on a presentation.
    @Binding var editSession: EditSession?
    @AppStorage("quickEditVisible") private var isQuickEditVisible = false
    @FocusState private var isWorkspaceFocused: Bool
    /// The presentation whose title is being edited. Navigation keys pass through to the field while set.
    @FocusState private var editingTitle: UUID?
    @State private var slidePendingDeletion: SlideDeletion?
    @State private var presentationEditingBackground: UUID?
    /// The playlist item whose section is at the top of the viewport.
    @State private var topItemID: UUID?
    /// Where each on-screen slide sits. A plain reference, so scrolling doesn't re-render the workspace.
    @State private var slideFrames = SlideFrames()

    private struct SlideDeletion: Identifiable {
        let slide: SlideDocument
        let presentationID: UUID
        var id: UUID { slide.id }
    }

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)]
    private static let coordinateSpace = "workspace"
    /// How much of a section's title must still show for it to count as on screen.
    private static let titleHeight: CGFloat = 40

    var body: some View {
        if coordinator.project.playlist.items.isEmpty {
            ContentUnavailableView(
                "Empty Playlist",
                systemImage: "rectangle.on.rectangle",
                description: Text("Create a new presentation to get started.")
            )
        } else {
            VStack(spacing: 0) {
                slides
                if isQuickEditVisible {
                    Divider()
                    SlideEditor(coordinator: coordinator)
                }
            }
            // AppKit otherwise gives first focus to the first title field, so Space/arrows meant for
            // slide navigation would overwrite a presentation title. (`.defaultFocus` is not enough.)
            .task { isWorkspaceFocused = true }
            .confirmationDialog(
                "Delete this slide?",
                isPresented: Binding(
                    get: { slidePendingDeletion != nil },
                    set: { if !$0 { slidePendingDeletion = nil } }
                ),
                presenting: slidePendingDeletion
            ) { deletion in
                Button("Delete", role: .destructive) {
                    coordinator.deleteSlide(deletion.slide.id, inPresentation: deletion.presentationID)
                }
            } message: { _ in
                Text("If this slide is live, it stays on the audience output until you take another slide live.")
            }
        }
    }

    private var slides: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(coordinator.project.playlist.items) { item in
                            section(for: item)
                        }
                        // Room below the last presentation so it can scroll up to the top and be highlighted too.
                        // A spacer, not `contentMargins`: margins also shift where `scrollTo(_:anchor:)` aims.
                        Color.clear.frame(height: max(0, viewport.size.height - 160))
                    }
                }
                .coordinateSpace(name: Self.coordinateSpace)
                // Measured positions rather than `scrollPosition(id:)`, which misses scrolls the app makes itself
                // (following the live slide), so the sidebar would lag behind.
                .onPreferenceChange(SlideFramesKey.self) { slideFrames.frames = $0 }
                .onPreferenceChange(SectionOffsetsKey.self) { offsets in
                    let id = Self.currentItem(
                        in: offsets,
                        order: coordinator.project.playlist.items.map(\.id),
                        viewportHeight: viewport.size.height
                    )
                    if id != topItemID { topItemID = id }
                }
                .focusable()
                .focused($isWorkspaceFocused)
                .focusEffectDisabled()
                // The title fields sit inside this view, so without the guard Space typed into a title
                // would advance the live slide.
                .onKeyPress(.rightArrow) { navigate { coordinator.nextSlide() } }
                .onKeyPress(.space) { navigate { coordinator.nextSlide() } }
                .onKeyPress(.leftArrow) { navigate { coordinator.previousSlide() } }
                .onKeyPress(.return) { navigate { coordinator.takeLive() } }
                .onAppear {
                    if let selected = coordinator.state.selectedItemID {
                        proxy.scrollTo(selected, anchor: .top)
                    }
                }
                // Scrolling moves the sidebar highlight. This never scrolls back, so the two can't fight.
                .onChange(of: topItemID) { _, itemID in
                    if let itemID, itemID != coordinator.state.selectedItemID {
                        coordinator.selectItem(itemID)
                    }
                }
                .onChange(of: scrollRequest) { _, itemID in
                    guard let itemID else { return }
                    withAnimation { proxy.scrollTo(itemID, anchor: .top) }
                    scrollRequest = nil
                }
                // Keep the live and cued slides on screen. Next/Previous crossing into another presentation
                // brings it into view this way.
                .onChange(of: coordinator.state.live?.position) { _, position in
                    if let position { reveal(position.slideID, viewportHeight: viewport.size.height, proxy: proxy) }
                }
                .onChange(of: coordinator.state.preview) { _, position in
                    if let position { reveal(position.slideID, viewportHeight: viewport.size.height, proxy: proxy) }
                }
            }
        }
    }

    private func navigate(_ command: () -> CommandResult) -> KeyPress.Result {
        guard editingTitle == nil else { return .ignored }
        _ = command()
        return .handled
    }

    /// Scrolls only if the slide isn't fully visible: a slide below the view lands at the bottom edge, one
    /// above it near the top, leaving room for its presentation's title. (`scrollTo` without an anchor jumps
    /// even when the slide is already visible.) A slide that isn't laid out yet is centred.
    private func reveal(_ slideID: UUID, viewportHeight: CGFloat, proxy: ScrollViewProxy) {
        let anchor: UnitPoint
        if let frame = slideFrames.frames[slideID] {
            if frame.minY >= 0 && frame.maxY <= viewportHeight { return }
            anchor = frame.minY < 0 ? UnitPoint(x: 0.5, y: 0.3) : .bottom
        } else {
            anchor = .center
        }
        withAnimation { proxy.scrollTo(slideID, anchor: anchor) }
    }

    /// The first presentation whose title is visible. When a long presentation fills the view and no
    /// title shows, the one covering the top edge.
    private static func currentItem(in offsets: [UUID: CGFloat], order: [UUID], viewportHeight: CGFloat) -> UUID? {
        let onScreen = order.filter { offsets[$0] != nil }
        let titleVisible = onScreen.first { id in
            let top = offsets[id]!
            return top >= -titleHeight / 2 && top <= viewportHeight - titleHeight
        }
        return titleVisible ?? onScreen.last { offsets[$0]! <= 0 }
    }

    @ViewBuilder
    private func section(for item: PresentationItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let presentation = coordinator.project.presentation(withID: item.presentationID) {
                header(presentation: presentation, itemID: item.id)
                grid(presentation: presentation, itemID: item.id)
            } else {
                Label("Missing presentation", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(16)
            }
            Divider()
        }
        .id(item.id)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SectionOffsetsKey.self,
                    value: [item.id: geometry.frame(in: .named(Self.coordinateSpace)).minY]
                )
            }
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
            .focused($editingTitle, equals: presentation.id)
            .onSubmit { isWorkspaceFocused = true }

            if coordinator.state.live?.position.itemID == itemID {
                StateBadge(text: "LIVE", color: .red)
            }

            Button {
                presentationEditingBackground = presentation.id
            } label: {
                Label("Background", systemImage: "photo.on.rectangle")
            }
            .help("Background for every slide in this presentation that doesn't set its own")
            .popover(isPresented: Binding(
                get: { presentationEditingBackground == presentation.id },
                set: { if !$0 { presentationEditingBackground = nil } }
            ), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Presentation Background").font(.headline)
                    BackgroundInspector(coordinator: coordinator, target: .presentation(presentation.id))
                }
                .padding(16)
                .frame(width: 380)
            }

            Button {
                coordinator.addSlide(toItem: itemID)
            } label: {
                Label("Add Slide", systemImage: "plus.rectangle")
            }

            Button {
                // Open on the cued slide when it's in this presentation, else the first slide.
                let cued = coordinator.state.preview.flatMap { $0.itemID == itemID ? $0.slideID : nil }
                editSession = EditSession(itemID: itemID, presentationID: presentation.id, initialSlideID: cued)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .help("Open this presentation in the slide editor")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func grid(presentation: PresentationDocument, itemID: UUID) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(presentation.slides.enumerated()), id: \.element.id) { index, slide in
                let position = SlidePosition(itemID: itemID, slideID: slide.id)
                SlideThumbnail(
                    slide: presentation.rendered(slide),
                    number: index + 1,
                    isCued: coordinator.state.preview == position,
                    isLive: coordinator.state.live?.position == position
                )
                .id(slide.id)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SlideFramesKey.self,
                            value: [slide.id: geometry.frame(in: .named(Self.coordinateSpace))]
                        )
                    }
                }
                .onTapGesture {
                    isWorkspaceFocused = true
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
                        slidePendingDeletion = SlideDeletion(slide: slide, presentationID: presentation.id)
                    }
                }
            }
        }
        .padding(16)
    }
}

/// Each on-screen section's top edge, relative to the top of the workspace's visible area.
private struct SectionOffsetsKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Each on-screen slide's frame, relative to the workspace's visible area.
private struct SlideFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private final class SlideFrames {
    var frames: [UUID: CGRect] = [:]
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
                if let label = slide.slide.label { GroupLabelTag(label: label) }
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
