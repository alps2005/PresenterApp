import AppKit
import SwiftUI
import PresenterCore

/// Makes and edits stage layouts: the list of layouts, a live preview where regions are dragged and resized, and
/// the selected region's settings. Changes apply as they're made (and undo with ⌘Z); the stage display follows.
struct StageLayoutEditor: View {
    let coordinator: PresentationCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var layoutID: UUID?
    @State private var regionID: UUID?
    @State private var pendingDeletion: StageLayout?

    private var layout: StageLayout? { layoutID.flatMap { coordinator.project.stageLayout(withID: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Stage Layouts").font(.title2.bold())
            HStack(alignment: .top, spacing: Spacing.lg) {
                layoutList
                    .frame(width: 190)
                if let layout {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header(layout)
                        StageLayoutCanvas(coordinator: coordinator, layout: layout, selection: $regionID)
                            .aspectRatio(16 / 9, contentMode: .fit)
                        Text("Point at a region to see its name. Drag it to move it and its handles to resize it. Hold ⌘ to place it freely. The preview shows what's live now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    StageRegionInspector(coordinator: coordinator, layout: layout, regionID: $regionID)
                        .frame(width: 240)
                } else {
                    ContentUnavailableView("No Layout Selected", systemImage: "rectangle.3.group",
                                           description: Text("Choose a layout, or make one with +."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack {
                Text("The standard look isn't a layout; its clock, timer and notes are set in the Stage tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 1040, height: 600)
        .onAppear { layoutID = coordinator.project.stage.layoutID ?? coordinator.project.stageLayouts.first?.id }
        .onChange(of: layoutID) { regionID = nil }
        .confirmDeletion("Delete “\(pendingDeletion?.name ?? "")”?",
                         message: pendingDeletion.map(deletionMessage) ?? "",
                         of: $pendingDeletion) { layout in
            coordinator.deleteStageLayout(layout.id)
            if layoutID == layout.id { layoutID = coordinator.project.stageLayouts.first?.id }
        }
    }

    private var layoutList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            List(selection: $layoutID) {
                ForEach(coordinator.project.stageLayouts) { layout in
                    HStack {
                        Text(layout.name.isEmpty ? "Untitled" : layout.name)
                            .lineLimit(1)
                        Spacer()
                        if coordinator.project.stage.layoutID == layout.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                                .help("On the stage display now")
                                .accessibilityLabel("In use")
                        }
                    }
                    .tag(layout.id)
                    .contextMenu {
                        Button("Duplicate") { duplicate(layout) }
                        Button("Delete…", role: .destructive) { pendingDeletion = layout }
                    }
                }
            }
            .listStyle(.bordered)
            HStack(spacing: Spacing.sm) {
                Menu {
                    Button("New Layout") { add(basedOn: nil) }
                    if let layout { Button("Copy of “\(layout.name)”") { duplicate(layout) } }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Make a layout")
                .accessibilityLabel("Add Layout")
                Button {
                    pendingDeletion = layout
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(layout == nil)
                .help("Delete the selected layout")
                .accessibilityLabel("Delete Layout")
            }
        }
    }

    private func header(_ layout: StageLayout) -> some View {
        HStack(spacing: Spacing.md) {
            TextField("Name", text: Binding(get: { layout.name }, set: { name in edit { $0.name = name } }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            ColorPicker("Background", selection: Binding(
                get: { layout.background.color },
                set: { color in edit { $0.background = RGBAColor(color) } }
            ), supportsOpacity: false)
            .fixedSize()
            Spacer()
            Menu("Add Region") {
                ForEach(StageRegion.Kind.all, id: \.self) { kind in
                    Button(kind.title) { addRegion(kind) }
                }
            }
            .fixedSize()
            if coordinator.project.stage.layoutID == layout.id {
                Text("On Stage").font(.caption.bold()).foregroundStyle(.secondary)
            } else {
                Button("Use on Stage") { coordinator.setStageLayout(layout.id) }
            }
        }
    }

    private func edit(_ change: (inout StageLayout) -> Void) {
        guard var layout else { return }
        change(&layout)
        coordinator.updateStageLayout(layout)
    }

    private func add(basedOn source: UUID?) {
        if let layout = coordinator.addStageLayout(named: "New Layout", basedOn: source) { layoutID = layout.id }
    }

    private func duplicate(_ layout: StageLayout) {
        if let copy = coordinator.addStageLayout(named: "\(layout.name) Copy", basedOn: layout.id) { layoutID = copy.id }
    }

    private func addRegion(_ kind: StageRegion.Kind) {
        let region = StageRegion(kind: kind, frame: .centered(width: 0.4, height: kind.hasText ? 0.15 : 0.3),
                                 fontSize: 64, color: kind == .message ? .black : .white)
        edit { $0.regions.append(region) }
        regionID = region.id
    }

    private func deletionMessage(_ layout: StageLayout) -> String {
        coordinator.project.stage.layoutID == layout.id
            ? "The stage display is using it, so it goes back to the standard look. You can undo this."
            : "You can undo this."
    }
}

/// The layout as the stage display shows it now, with the regions outlined so they can be selected, dragged and
/// resized.
private struct StageLayoutCanvas: View {
    let coordinator: PresentationCoordinator
    let layout: StageLayout
    @Binding var selection: UUID?

    /// The frame being dragged, shown until it's committed when the drag ends.
    @State private var draft: (regionID: UUID, frame: NormalizedRect)?
    @State private var dragOrigin: NormalizedRect?
    @State private var guides: Snapping.Result?
    /// The region under the pointer, named with a tag. Only that one: regions may overlap, and an always-on tag
    /// would cover what the region below shows.
    @State private var hoveredRegionID: UUID?

    private static let snapDistance: CGFloat = 6
    private static let minimumSize = 0.03

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    StageLayoutView(coordinator: coordinator, layout: shown, now: context.date)
                }
                .allowsHitTesting(false)

                // Clicking empty space deselects.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }

                ForEach(shown.regions) { region in
                    let rect = rect(region.frame, in: size)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .background(Color.white.opacity(0.001))
                        .overlay(alignment: .bottomLeading) {
                            Text(region.kind.title)
                                .font(.caption2)
                                .padding(.horizontal, 3)
                                .background(Color.black.opacity(0.6))
                                .foregroundStyle(.white)
                                .opacity(region.id == hoveredRegionID && region.id != selection ? 1 : 0)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onHover { inside in
                            if inside {
                                hoveredRegionID = region.id
                            } else if hoveredRegionID == region.id {
                                hoveredRegionID = nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .named(EditorCanvas.stageSpace))
                                .onChanged { value in move(region, by: value.translation, in: size) }
                                .onEnded { _ in commit() }
                        )
                        .simultaneousGesture(TapGesture().onEnded { selection = region.id })
                        .help(region.kind.title)
                        .accessibilityLabel(region.kind.title)
                        .accessibilityAddTraits(.isButton)
                }

                if let guides { guideLines(guides, size: size) }

                if let region = shown.regions.first(where: { $0.id == selection }) {
                    SelectionChrome(rect: rect(region.frame, in: size)) { handle, translation, ended in
                        resize(region, handle: handle, by: translation, in: size)
                        if ended { commit() }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: EditorCanvas.stageSpace)
            .clipped()
            .overlay { Rectangle().strokeBorder(Color.secondary.opacity(0.4)) }
        }
    }

    /// The layout with the region being dragged in its new place.
    private var shown: StageLayout {
        guard let draft, let index = layout.regions.firstIndex(where: { $0.id == draft.regionID }) else { return layout }
        var shown = layout
        shown.regions[index].frame = draft.frame
        return shown
    }

    private func rect(_ frame: NormalizedRect, in size: CGSize) -> CGRect {
        CGRect(x: frame.x * size.width, y: frame.y * size.height, width: frame.width * size.width, height: frame.height * size.height)
    }

    private func move(_ region: StageRegion, by translation: CGSize, in size: CGSize) {
        if dragOrigin == nil {
            dragOrigin = region.frame
            selection = region.id
        }
        guard let origin = dragOrigin else { return }
        var frame = origin
        frame.x += translation.width / size.width
        frame.y += translation.height / size.height
        frame = frame.clampedToCanvas()
        if NSEvent.modifierFlags.contains(.command) {
            guides = nil
        } else {
            let result = Snapping.move(frame, among: otherFrames(than: region.id), tolerance: tolerance(size))
            frame = result.frame.clampedToCanvas()
            guides = result
        }
        draft = (region.id, frame)
    }

    private func resize(_ region: StageRegion, handle: SelectionChrome.Handle, by translation: CGSize, in size: CGSize) {
        if dragOrigin == nil { dragOrigin = region.frame }
        guard let origin = dragOrigin else { return }
        let edges = Snapping.Edges(left: handle.movesLeft, right: handle.movesRight, top: handle.movesTop, bottom: handle.movesBottom)
        var frame = Snapping.resized(origin, moving: edges, by: translation.width / size.width,
                                     translation.height / size.height, minimumSize: Self.minimumSize)
        if NSEvent.modifierFlags.contains(.command) {
            guides = nil
        } else {
            let result = Snapping.resize(frame, moving: edges, among: otherFrames(than: region.id),
                                         tolerance: tolerance(size), minimumSize: Self.minimumSize)
            frame = result.frame
            guides = result
        }
        draft = (region.id, frame)
    }

    private func commit() {
        defer {
            draft = nil
            dragOrigin = nil
            guides = nil
        }
        guard let draft, let index = layout.regions.firstIndex(where: { $0.id == draft.regionID }) else { return }
        var updated = layout
        updated.regions[index].frame = draft.frame
        coordinator.updateStageLayout(updated)
    }

    private func otherFrames(than regionID: UUID) -> [NormalizedRect] {
        layout.regions.filter { $0.id != regionID }.map(\.frame)
    }

    private func tolerance(_ size: CGSize) -> (x: Double, y: Double) {
        (x: Self.snapDistance / size.width, y: Self.snapDistance / size.height)
    }

    private func guideLines(_ guides: Snapping.Result, size: CGSize) -> some View {
        Path { path in
            for x in guides.verticalGuides {
                path.move(to: CGPoint(x: x * size.width, y: 0))
                path.addLine(to: CGPoint(x: x * size.width, y: size.height))
            }
            for y in guides.horizontalGuides {
                path.move(to: CGPoint(x: 0, y: y * size.height))
                path.addLine(to: CGPoint(x: size.width, y: y * size.height))
            }
        }
        .stroke(Color.yellow, lineWidth: 1)
        .allowsHitTesting(false)
    }
}

/// The selected region's settings.
private struct StageRegionInspector: View {
    let coordinator: PresentationCoordinator
    let layout: StageLayout
    @Binding var regionID: UUID?

    var body: some View {
        if let region = layout.regions.first(where: { $0.id == regionID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(region.kind.title).font(.headline)
                    kindControls(region)
                    if region.kind.hasText {
                        HStack {
                            Text("Size").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { region.fontSize }, set: { size in edit(region) { $0.fontSize = size.rounded() } }),
                                   in: StageRegion.fontSizeRange)
                                .accessibilityLabel("Text size")
                            Text("\(Int(region.fontSize)) pt")
                                .monospacedDigit()
                                .frame(width: Widths.valueLabel, alignment: .trailing)
                        }
                        ColorPicker(region.kind == .message ? "Text on the yellow bar" : "Colour", selection: Binding(
                            get: { region.color.color },
                            set: { color in edit(region) { $0.color = RGBAColor(color) } }
                        ))
                        Picker("Alignment", selection: Binding(get: { region.alignment }, set: { alignment in edit(region) { $0.alignment = alignment } })) {
                            Image(systemName: "text.alignleft").tag(HorizontalTextAlignment.leading).accessibilityLabel("Left")
                            Image(systemName: "text.aligncenter").tag(HorizontalTextAlignment.center).accessibilityLabel("Centre")
                            Image(systemName: "text.alignright").tag(HorizontalTextAlignment.trailing).accessibilityLabel("Right")
                        }
                        .pickerStyle(.segmented)
                    }
                    if region.kind.hasLabel {
                        Toggle(region.kind == .nextText ? "Show “NEXT” and the group" : "Show the timer's name", isOn: Binding(
                            get: { region.showsLabel },
                            set: { shows in edit(region) { $0.showsLabel = shows } }
                        ))
                    }
                    Divider()
                    HStack {
                        Button("Bring to Front") { reorder(region, toFront: true) }
                        Button("Send to Back") { reorder(region, toFront: false) }
                    }
                    .controlSize(.small)
                    Button("Delete Region", role: .destructive) {
                        regionID = nil
                        coordinator.updateStageLayout(StageLayout(id: layout.id, name: layout.name,
                                                                  regions: layout.regions.filter { $0.id != region.id },
                                                                  background: layout.background))
                    }
                    Text(region.kind.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Click a region in the preview to change it, or add one with Add Region.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func kindControls(_ region: StageRegion) -> some View {
        switch region.kind {
        case .timer(let timerID):
            Picker("Timer", selection: Binding(get: { timerID }, set: { id in edit(region) { $0.kind = .timer(id) } })) {
                Text("The stage's timer").tag(UUID?.none)
                ForEach(coordinator.project.timers) { Text($0.name).tag(Optional($0.id)) }
            }
        case .text(let text):
            TextField("Text", text: Binding(get: { text }, set: { value in edit(region) { $0.kind = .text(value) } }),
                      axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
        default:
            EmptyView()
        }
    }

    private func edit(_ region: StageRegion, _ change: (inout StageRegion) -> Void) {
        guard let index = layout.regions.firstIndex(where: { $0.id == region.id }) else { return }
        var updated = layout
        change(&updated.regions[index])
        coordinator.updateStageLayout(updated)
    }

    private func reorder(_ region: StageRegion, toFront: Bool) {
        var updated = layout
        updated.regions.removeAll { $0.id == region.id }
        if toFront { updated.regions.append(region) } else { updated.regions.insert(region, at: 0) }
        coordinator.updateStageLayout(updated)
    }
}

extension StageRegion.Kind {
    var hasLabel: Bool {
        switch self {
        case .nextText, .timer: true
        default: false
        }
    }

    /// What the region shows, for the inspector.
    var caption: String {
        switch self {
        case .liveText: "The live slide's words, shrinking to fit."
        case .nextText: "The next slide's words, so singers see what's coming."
        case .liveSlide: "The live slide as the audience sees it."
        case .nextSlide: "The next slide as the audience will see it."
        case .clock: "The time of day."
        case .timer: "A timer's value. Countdowns turn red when they run over."
        case .notes: "The live slide's notes. Edits show straight away."
        case .message: "The message sent from the Stage tab, on a yellow bar. Empty while there's no message."
        case .text: "Fixed words, such as a reminder for the band."
        }
    }
}
