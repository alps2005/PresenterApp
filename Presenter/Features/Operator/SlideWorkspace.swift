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
    @AppStorage("mediaBinVisible") private var isMediaBinVisible = false
    @AppStorage("audioBinVisible") private var isAudioBinVisible = false
    /// Thumbnail width, from the size slider at the bottom right of the workspace.
    @AppStorage("thumbnailWidth") private var thumbnailWidth = 180.0
    @State private var reflowPresentationID: UUID?
    /// The presentation whose title is being renamed in place.
    @State private var renamingPresentationID: UUID?
    @State private var arrangementDraft: ArrangementDraft?
    @FocusState private var isWorkspaceFocused: Bool
    /// The presentation whose title is being edited. Navigation keys pass through to the field while set.
    @FocusState private var editingTitle: UUID?
    @State private var slidePendingDeletion: SlideDeletion?
    @State private var presentationEditingBackground: UUID?
    @State private var goToNextTarget: GoToNextTarget?
    /// The presentation whose Slideshow sheet (Custom…) is open.
    @State private var slideshowCustomID: UUID?
    /// The presentation whose Slideshow popover is open.
    @State private var slideshowPopoverID: UUID?
    /// The playlist item whose section is at the top of the viewport.
    @State private var topItemID: UUID?
    /// Where each on-screen slide sits. A plain reference, so scrolling doesn't re-render the workspace.
    @State private var slideFrames = SlideFrames()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct GoToNextTarget: Identifiable {
        let slideID: UUID
        let presentationID: UUID
        var id: UUID { slideID }
    }

    private struct SlideDeletion: Identifiable {
        let slide: SlideDocument
        let presentationID: UUID
        var id: UUID { slide.id }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth * 1.45), spacing: Spacing.lg)]
    }

    static let thumbnailWidths: ClosedRange<Double> = 120...420
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
                if isMediaBinVisible {
                    Divider()
                    MediaBin(coordinator: coordinator)
                }
                if isAudioBinVisible {
                    Divider()
                    AudioBin(coordinator: coordinator)
                }
            }
            // AppKit otherwise gives first focus to the first title field, so Space/arrows meant for
            // slide navigation would overwrite a presentation title. (`.defaultFocus` is not enough.)
            .task { isWorkspaceFocused = true }
            .sheet(isPresented: Binding(
                get: { reflowPresentationID != nil },
                set: { if !$0 { reflowPresentationID = nil } }
            )) {
                if let reflowPresentationID {
                    ReflowSheet(coordinator: coordinator, presentationID: reflowPresentationID)
                }
            }
            .sheet(item: $arrangementDraft) { draft in
                ArrangementSheet(coordinator: coordinator, draft: draft)
            }
            .sheet(item: $goToNextTarget) { target in
                GoToNextSheet(coordinator: coordinator, slideID: target.slideID, presentationID: target.presentationID)
            }
            .sheet(isPresented: Binding(
                get: { slideshowCustomID != nil },
                set: { if !$0 { slideshowCustomID = nil } }
            )) {
                if let slideshowCustomID {
                    SlideshowIntervalSheet(coordinator: coordinator, presentationID: slideshowCustomID)
                }
            }
            .onChange(of: reflowPresentationID) { _, id in if id == nil { isWorkspaceFocused = true } }
            .onChange(of: arrangementDraft?.id) { _, id in if id == nil { isWorkspaceFocused = true } }
            .onChange(of: goToNextTarget?.id) { _, id in if id == nil { isWorkspaceFocused = true } }
            .onChange(of: slideshowCustomID) { _, id in if id == nil { isWorkspaceFocused = true } }
            .confirmSlideDeletion(of: $slidePendingDeletion) { deletion in
                coordinator.deleteSlide(deletion.slide.id, inPresentation: deletion.presentationID)
            }
        }
    }

    private var slides: some View {
        slideScroll
            .overlay(alignment: .bottomTrailing) { sizeSlider }
    }

    /// Like ProPresenter's slide size slider, bottom right of the slide view.
    private var sizeSlider: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "square.grid.3x3").font(.caption).accessibilityHidden(true)
            Slider(value: $thumbnailWidth, in: Self.thumbnailWidths)
                .frame(width: 110)
                .controlSize(.mini)
                .accessibilityLabel("Thumbnail size")
            Image(systemName: "square.grid.2x2").font(.caption).accessibilityHidden(true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Palette.panelRaised, in: Capsule())
        .hairlineBorder(Capsule())
        .padding(Spacing.md)
        .help("Thumbnail size")
    }

    private var slideScroll: some View {
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
                .hardScrollEdges()
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
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(itemID, anchor: .top) }
                    scrollRequest = nil
                }
                // Keep the live and cued slides on screen. Next/Previous crossing into another presentation
                // brings it into view this way.
                .onChange(of: coordinator.state.live?.position) { _, position in
                    if let position { reveal(position, viewportHeight: viewport.size.height, proxy: proxy) }
                }
                .onChange(of: coordinator.state.preview) { _, position in
                    if let position { reveal(position, viewportHeight: viewport.size.height, proxy: proxy) }
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
    private func reveal(_ position: SlidePosition, viewportHeight: CGFloat, proxy: ScrollViewProxy) {
        let key = position.thumbnailKey
        let anchor: UnitPoint
        if let frame = slideFrames.frames[key] {
            if frame.minY >= 0 && frame.maxY <= viewportHeight { return }
            anchor = frame.minY < 0 ? UnitPoint(x: 0.5, y: 0.3) : .bottom
        } else {
            anchor = .center
        }
        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(key, anchor: anchor) }
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
                WarningLabel("Missing presentation")
                    .font(.body)
                    .padding(Spacing.lg)
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
            title(presentation)
                .layoutPriority(1)

            if coordinator.state.live?.position.itemID == itemID {
                StateBadge(.live)
            }

            Spacer(minLength: 8)

            // Full labels when they fit; icons only (with tooltips) when the workspace is narrow, so the
            // presentation's title is never squeezed.
            ViewThatFits(in: .horizontal) {
                headerButtons(presentation: presentation, itemID: itemID)
                    .labelStyle(.titleAndIcon)
                headerButtons(presentation: presentation, itemID: itemID, compactSlideshow: true)
                    .labelStyle(.titleAndIcon)
                headerButtons(presentation: presentation, itemID: itemID)
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }

    /// The title is plain text until clicked. An always-present text field would get keyboard focus whenever a
    /// sheet closed, and Space and the arrow keys meant for the slides would type into it.
    @ViewBuilder
    private func title(_ presentation: PresentationDocument) -> some View {
        if renamingPresentationID == presentation.id {
            TextField("Title", text: Binding(
                get: { presentation.title },
                set: { coordinator.renamePresentation(presentation.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.title2.bold())
            .focused($editingTitle, equals: presentation.id)
            .onAppear { editingTitle = presentation.id }
            .onSubmit { finishRenaming() }
            .onChange(of: editingTitle) { _, focused in
                if focused != presentation.id { finishRenaming() }
            }
        } else {
            Text(presentation.title.isEmpty ? "Untitled" : presentation.title)
                .font(.title2.bold())
                .lineLimit(1)
                .foregroundStyle(presentation.title.isEmpty ? .secondary : .primary)
                .contentShape(Rectangle())
                .onTapGesture { renamingPresentationID = presentation.id }
                .help("Click to rename")
        }
    }

    private func finishRenaming() {
        renamingPresentationID = nil
        editingTitle = nil
        isWorkspaceFocused = true
    }

    /// `compactSlideshow` shows the Slideshow menu as its icon, the first thing to give up its label when space runs out.
    private func headerButtons(presentation: PresentationDocument, itemID: UUID, compactSlideshow: Bool = false) -> some View {
        HStack {
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
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Presentation Background").font(.headline)
                    BackgroundInspector(coordinator: coordinator, target: .presentation(presentation.id))
                }
                .padding(Spacing.lg)
                .frame(width: 380)
            }

            Button {
                coordinator.addSlide(toItem: itemID)
            } label: {
                Label("Add Slide", systemImage: "plus.rectangle")
            }
            .help("Add a slide")

            if !presentation.groupNames.isEmpty || !presentation.arrangements.isEmpty {
                arrangementMenu(presentation: presentation)
            }

            if compactSlideshow {
                slideshowMenu(presentation: presentation).labelStyle(.iconOnly)
            } else {
                slideshowMenu(presentation: presentation)
            }

            Button {
                reflowPresentationID = presentation.id
            } label: {
                Label("Reflow", systemImage: "text.alignleft")
            }
            .help("Edit all of this presentation's words as one document")

            Button {
                // Open on the cued slide when it's in this presentation, else the first slide.
                let cued = coordinator.state.preview.flatMap { $0.itemID == itemID ? $0.slideID : nil }
                editSession = EditSession(itemID: itemID, presentationID: presentation.id, initialSlideID: cued)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .help("Open this presentation in the slide editor")
        }
        .fixedSize()
    }

    private func grid(presentation: PresentationDocument, itemID: UUID) -> some View {
        LazyVGrid(columns: columns, spacing: Spacing.lg) {
            // In play order: the active arrangement's order, with repeated slides shown again.
            ForEach(Array(presentation.arrangedSlides.enumerated()), id: \.element) { index, arranged in
                if let slide = presentation.slide(withID: arranged.slideID) {
                    thumbnail(slide, number: index + 1, occurrence: arranged.occurrence, presentation: presentation, itemID: itemID)
                }
            }
        }
        .padding(Spacing.lg)
    }

    private func thumbnail(
        _ slide: SlideDocument,
        number: Int,
        occurrence: Int,
        presentation: PresentationDocument,
        itemID: UUID
    ) -> some View {
        let position = SlidePosition(itemID: itemID, slideID: slide.id, occurrence: occurrence)
        let advance = coordinator.state.autoAdvance
        return SlideThumbnail(
            slide: coordinator.project.rendered(slide, in: presentation),
            number: number,
            isCued: coordinator.state.preview == position,
            isLive: coordinator.state.live?.position == position,
            advanceSeconds: slide.goToNext?.seconds ?? presentation.slideshowInterval,
            advance: advance?.position == position ? advance : nil
        )
        .id(position.thumbnailKey)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SlideFramesKey.self,
                    value: [position.thumbnailKey: geometry.frame(in: .named(Self.coordinateSpace))]
                )
            }
        }
        .onTapGesture {
            if renamingPresentationID != nil { finishRenaming() }
            isWorkspaceFocused = true
            coordinator.cueSlide(slide.id, inItem: itemID, occurrence: occurrence)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            coordinator.takeLive(slideID: slide.id, inItem: itemID, occurrence: occurrence)
        })
        .contextMenu {
            Button("Take Live") {
                coordinator.takeLive(slideID: slide.id, inItem: itemID, occurrence: occurrence)
            }
            Button("Go To Next Timer…") {
                goToNextTarget = GoToNextTarget(slideID: slide.id, presentationID: presentation.id)
            }
            if slide.goToNext != nil {
                Button("Remove Go To Next Timer") {
                    coordinator.setGoToNext(nil, forSlides: [slide.id], inPresentation: presentation.id)
                }
            }
            Divider()
            Button("Delete Slide…", role: .destructive) {
                slidePendingDeletion = SlideDeletion(slide: slide, presentationID: presentation.id)
            }
        }
    }

    // MARK: Slideshow

    /// Like ProPresenter's Slideshow button: every slide moves on by itself after the chosen time, looping.
    /// A button and popover, not a `Menu`: a menu in every presentation header made scrolling the workspace noticeably
    /// heavier (measured). Custom… opens the Slideshow sheet.
    private func slideshowMenu(presentation: PresentationDocument) -> some View {
        Button {
            slideshowPopoverID = presentation.id
        } label: {
            // Filled while on, so the icon alone (in a narrow header) still says so.
            Label(presentation.slideshowInterval.map { "Slideshow \(AdvanceTime.label($0))" } ?? "Slideshow",
                  systemImage: presentation.slideshowInterval == nil ? "play.square.stack" : "play.square.stack.fill")
        }
        .help("Move through every slide by itself, looping. A slide's own Go To Next Timer comes first.")
        .popover(isPresented: Binding(
            get: { slideshowPopoverID == presentation.id },
            set: { if !$0 { slideshowPopoverID = nil } }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Slideshow").font(.headline)
                Picker("Slideshow", selection: Binding(
                    get: { presentation.slideshowInterval },
                    set: {
                        coordinator.setSlideshowInterval($0, presentation: presentation.id)
                        slideshowPopoverID = nil
                    }
                )) {
                    Text("Off").tag(Double?.none)
                    ForEach(AdvanceTime.slideshowPresets, id: \.self) { seconds in
                        Text("Every \(AdvanceTime.label(seconds))").tag(Optional(seconds))
                    }
                    // A custom interval still shows as chosen.
                    if let interval = presentation.slideshowInterval, !AdvanceTime.slideshowPresets.contains(interval) {
                        Text("Every \(AdvanceTime.label(interval))").tag(Optional(interval))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Button("Custom…") {
                    slideshowPopoverID = nil
                    slideshowCustomID = presentation.id
                }
                Text("Every slide moves on by itself and loops. A slide's own Go To Next Timer comes first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.lg)
            .frame(width: 260)
        }
    }

    // MARK: Arrangements

    private func arrangementMenu(presentation: PresentationDocument) -> some View {
        Menu {
            Picker("Arrangement", selection: Binding(
                get: { presentation.activeArrangementID },
                set: { coordinator.setActiveArrangement($0, inPresentation: presentation.id) }
            )) {
                Text("Slide Order").tag(UUID?.none)
                ForEach(presentation.arrangements) { arrangement in
                    Text(arrangement.name).tag(Optional(arrangement.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("New Arrangement…") {
                arrangementDraft = ArrangementDraft(presentationID: presentation.id, arrangement: nil)
            }
            if let active = presentation.activeArrangement {
                Button("Edit “\(active.name)”…") {
                    arrangementDraft = ArrangementDraft(presentationID: presentation.id, arrangement: active)
                }
            }
        } label: {
            Label(presentation.activeArrangement?.name ?? "Slide Order", systemImage: "list.number")
        }
        .fixedSize()
        .help("The order this presentation's groups play in")
    }
}

/// Which presentation's arrangement is being created or edited.
struct ArrangementDraft: Identifiable {
    let presentationID: UUID
    /// Nil for a new arrangement.
    let arrangement: Arrangement?
    var id: String { "\(presentationID)-\(arrangement?.id.uuidString ?? "new")" }
}

extension SlidePosition {
    /// Identifies a thumbnail in the workspace: the same slide can appear in two playlist items, and more than
    /// once in an arrangement.
    var thumbnailKey: String { "\(itemID)-\(slideID)-\(occurrence)" }
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
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private final class SlideFrames {
    var frames: [String: CGRect] = [:]
}

struct SlideThumbnail: View {
    let slide: RenderedSlide
    let number: Int
    let isCued: Bool
    let isLive: Bool
    /// How long the slide stays up before moving on by itself (Go To Next or Slideshow). Nil: until the operator moves.
    var advanceSeconds: Double? = nil
    /// The countdown, on the live slide while it runs.
    var advance: AutoAdvance? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SlideRenderView(scene: .slide(slide))
                .aspectRatio(16 / 9, contentMode: .fit)
                .tileFrame(TileState(isLive: isLive, isCued: isCued))
            HStack(spacing: Spacing.sm) {
                Text("\(number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let label = slide.slide.label { GroupLabelTag(label: label) }
                Spacer()
                if slide.slide.hasElementTransitions { ElementTransitionsMark() }
                if let advanceSeconds { AdvanceBadge(seconds: advanceSeconds, advance: advance) }
                if isCued { StateBadge(.cued) }
                if isLive { StateBadge(.live) }
            }
            .font(.caption)
        }
        .contentShape(Rectangle())
    }
}
