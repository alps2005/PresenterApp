import SwiftUI
import PresenterCore

/// The slide editor's right column. Format shows the selected element's settings (or the slide's when
/// nothing is selected), Animate the slide's transition and the selected element's own transitions, and Document the
/// presentation's settings.
struct EditorInspector: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument
    let slide: SlideDocument?
    let tab: EditorInspectorTab
    @Binding var selectedElementID: UUID?

    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var isConfirmingTransitionForAll = false
    @State private var importError: String?
    @State private var editingThemeID: UUID?
    /// A theme chosen for a presentation whose text is already formatted, waiting for Keep or Replace.
    @State private var pendingThemeID: UUID?

    /// The selected element as drawn: themed, so the controls show the look on the canvas.
    private var element: SlideElement? {
        guard let selectedElementID, let slide else { return nil }
        return coordinator.project.rendered(slide, in: presentation).slide.element(withID: selectedElementID)
    }

    private var theme: Theme? {
        coordinator.project.theme(for: presentation)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                switch tab {
                case .format: formatTab
                case .animate: animateTab
                case .document: documentTab
                }
            }
            .padding(Spacing.lg)
            .overflowGuard("Editor inspector", minimumWidth: Widths.editorInspector.min)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .solidPanel(Palette.sidebar)
        .hardScrollEdges()
        .controlSize(.small)
        .sheet(isPresented: Binding(get: { editingThemeID != nil }, set: { if !$0 { editingThemeID = nil } })) {
            if let editingThemeID {
                ThemeEditorSheet(coordinator: coordinator, themeID: editingThemeID)
            }
        }
    }

    private var title: String {
        switch tab {
        case .format:
            switch element {
            case .text: "Text"
            case .shape: "Shape"
            case .image: "Image"
            case nil: "Slide"
            }
        case .animate: "Animate"
        case .document: "Document"
        }
    }

    // MARK: Format

    @ViewBuilder
    private var formatTab: some View {
        if let slide {
            switch element {
            case .text(let text): textFormat(text, slide: slide)
            case .shape(let shape): shapeFormat(shape, slide: slide)
            case .image(let image): imageFormat(image, slide: slide)
            case nil: slideFormat(slide)
            }
        } else {
            placeholder("Select a slide to format it.")
        }
    }

    @ViewBuilder
    private func textFormat(_ text: TextElement, slide: SlideDocument) -> some View {
        section("Text") {
            TextStyleControls(style: Binding(
                get: { text.style },
                set: { style in
                    var updated = text
                    updated.style = style
                    update(.text(updated), on: slide)
                }
            ), layout: .narrow)
        }
        if let box = text.box {
            section("Vertical Alignment") {
                Picker("Vertical Alignment", selection: Binding(
                    get: { box.verticalAlignment },
                    set: { alignment in
                        var updated = text
                        updated.box?.verticalAlignment = alignment
                        update(.text(updated), on: slide)
                    }
                )) {
                    Image(systemName: "arrow.up.to.line").accessibilityLabel("Top").tag(VerticalTextAlignment.top)
                    Image(systemName: "arrow.up.and.down").accessibilityLabel("Middle").tag(VerticalTextAlignment.center)
                    Image(systemName: "arrow.down.to.line").accessibilityLabel("Bottom").tag(VerticalTextAlignment.bottom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        Text("Double-click the text on the slide to change the words.")
            .font(.caption)
            .foregroundStyle(.secondary)
        liveValues(text, slide: slide)
        if let theme {
            themeStatus(text, theme: theme, slide: slide)
        }
        arrange(.text(text), slide: slide)
    }

    /// Timers and the clock, shown live on the audience output and the stage display.
    private func liveValues(_ text: TextElement, slide: SlideDocument) -> some View {
        let known = Set(coordinator.project.timers.map { $0.name.lowercased() })
        let missing = LiveText.timerNames(in: text.text).filter { !known.contains($0.lowercased()) }
        return section("Live Values") {
            Menu("Insert") {
                ForEach(coordinator.project.timers) { timer in
                    Button("Timer: \(timer.name)") { insert("{timer:\(timer.name)}", into: text, on: slide) }
                }
                if !coordinator.project.timers.isEmpty { Divider() }
                Button("Clock") { insert("{clock}", into: text, on: slide) }
                Button("Clock with Seconds") { insert("{clock:seconds}", into: text, on: slide) }
            }
            .fixedSize()
            .help("Add a timer or the clock at the end of the text")
            ForEach(missing, id: \.self) { name in
                WarningLabel("There's no timer called “\(name)”, so it shows nothing. Make it in the Live panel's Timers tab, or fix the name.")
            }
            Text("The audience and the stage see the time, updating as it runs. Here it shows as typed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Adds a live value after the words, separated by a space.
    private func insert(_ token: String, into text: TextElement, on slide: SlideDocument) {
        // The stored element, not the themed copy, so the theme's look isn't written into it.
        guard case .text(var stored) = slide.element(withID: text.id) else { return }
        let separator = stored.text.isEmpty || stored.text.hasSuffix(" ") || stored.text.hasSuffix("\n") ? "" : " "
        stored.text += separator + token
        update(.text(stored), on: slide)
    }

    /// Whether the text follows the presentation's theme, in words, with the ways back and forth.
    @ViewBuilder
    private func themeStatus(_ text: TextElement, theme: Theme, slide: SlideDocument) -> some View {
        let overrides = slide.element(withID: text.id).flatMap { element -> Set<ThemedProperty>? in
            if case .text(let stored) = element { stored.overrides } else { nil }
        } ?? []
        section("Theme") {
            if overrides.isEmpty {
                Label("Follows “\(theme.name)”", systemImage: "paintpalette")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(Self.overrideText(overrides), systemImage: "paintbrush.pointed")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Revert to Theme") {
                    coordinator.revertToTheme(elementID: text.id, inPresentation: presentation.id)
                }
                .help("Use the theme's style and position for this text again")
            }
            Button("Update Theme from This Text") {
                coordinator.updateThemeFromText(text.id, slideID: slide.id, inPresentation: presentation.id)
            }
            .help("Give “\(theme.name)” this text's style and position. Every slide that follows the theme changes.")
        }
    }

    private static func overrideText(_ overrides: Set<ThemedProperty>) -> String {
        switch (overrides.contains(.style), overrides.contains(.box)) {
        case (true, true): "Own style and position"
        case (true, false): "Own style; position from the theme"
        default: "Own position; style from the theme"
        }
    }

    @ViewBuilder
    private func shapeFormat(_ shape: ShapeElement, slide: SlideDocument) -> some View {
        section("Shape") {
            Picker("Shape", selection: Binding(
                get: { shape.kind },
                set: { kind in
                    var updated = shape
                    updated.kind = kind
                    update(.shape(updated), on: slide)
                }
            )) {
                Image(systemName: "rectangle").accessibilityLabel("Rectangle").tag(ShapeElement.Kind.rectangle).help("Rectangle")
                Image(systemName: "app").accessibilityLabel("Rounded rectangle").tag(ShapeElement.Kind.roundedRectangle).help("Rounded rectangle")
                Image(systemName: "circle").accessibilityLabel("Oval").tag(ShapeElement.Kind.ellipse).help("Oval")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if shape.kind == .roundedRectangle {
                labeledSlider("Corners", value: Binding(
                    get: { shape.cornerRadius },
                    set: { radius in
                        var updated = shape
                        updated.cornerRadius = radius
                        update(.shape(updated), on: slide)
                    }
                ), in: 0...200)
            }
        }
        section("Fill") {
            optionalColor("Fill", color: shape.fill, defaultColor: RGBAColor(red: 0.2, green: 0.45, blue: 0.85)) { fill in
                var updated = shape
                updated.fill = fill
                update(.shape(updated), on: slide)
            }
        }
        section("Border") {
            optionalColor("Border", color: shape.stroke, defaultColor: .white) { stroke in
                var updated = shape
                updated.stroke = stroke
                update(.shape(updated), on: slide)
            }
            if shape.stroke != nil {
                labeledSlider("Width", value: Binding(
                    get: { shape.strokeWidth },
                    set: { width in
                        var updated = shape
                        updated.strokeWidth = width
                        update(.shape(updated), on: slide)
                    }
                ), in: 1...40)
            }
        }
        arrange(.shape(shape), slide: slide)
    }

    @ViewBuilder
    private func imageFormat(_ image: ImageElement, slide: SlideDocument) -> some View {
        section("Image") {
            Label(coordinator.project.asset(withID: image.assetID)?.originalFilename ?? "Unknown image", systemImage: "photo")
                .lineLimit(1)
                .truncationMode(.middle)
            if mediaLibrary.isMissing(image.assetID) {
                WarningLabel("The image file is missing or unreadable.")
            }
            Button("Replace Image…") { replaceImage(image, slide: slide) }
            if let importError {
                WarningLabel(importError)
            }
        }
        section("Scaling") {
            Picker("Scaling", selection: Binding(
                get: { image.scaling },
                set: { scaling in
                    var updated = image
                    updated.scaling = scaling
                    update(.image(updated), on: slide)
                }
            )) {
                Text("Fit").tag(ImageScaling.fit)
                Text("Fill").tag(ImageScaling.fill)
                Text("Stretch").tag(ImageScaling.stretch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            labeledSlider("Opacity", value: Binding(
                get: { image.opacity },
                set: { opacity in
                    var updated = image
                    updated.opacity = opacity
                    update(.image(updated), on: slide)
                }
            ), in: 0.05...1, format: { "\(Int($0 * 100))%" })
        }
        arrange(.image(image), slide: slide)
    }

    @ViewBuilder
    private func slideFormat(_ slide: SlideDocument) -> some View {
        section("Group") {
            HStack {
                TextField("None", text: Binding(
                    get: { slide.label ?? "" },
                    set: { coordinator.setLabel($0, slideID: slide.id, inPresentation: presentation.id) }
                ))
                .textFieldStyle(.roundedBorder)
                Menu("Choose") {
                    ForEach(["Verse 1", "Verse 2", "Verse 3", "Pre-Chorus", "Chorus", "Bridge", "Tag", "Intro", "Outro"], id: \.self) { name in
                        Button(name) { coordinator.setLabel(name, slideID: slide.id, inPresentation: presentation.id) }
                    }
                    Divider()
                    Button("None") { coordinator.setLabel("", slideID: slide.id, inPresentation: presentation.id) }
                }
                .fixedSize()
            }
            Text("Shown on the slide's thumbnail, like \"Verse 1\" or \"Coro\". The audience never sees it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        section("Background") {
            BackgroundInspector(coordinator: coordinator, target: .slide(slide.id, presentationID: presentation.id))
        }
        section("Go To Next") {
            GoToNextControls(timer: Binding(
                get: { slide.goToNext },
                set: { coordinator.setGoToNext($0, forSlides: [slide.id], inPresentation: presentation.id) }
            ))
        }
        // Props are overlays shown on their own, never taken live as slides, so they have no audio.
        if presentation.id != coordinator.project.props.id {
            section("Audio") {
                AudioCueControls(coordinator: coordinator, cue: Binding(
                    get: { slide.audioCue },
                    set: { coordinator.setAudioCue($0, slideID: slide.id, inPresentation: presentation.id) }
                ))
            }
            section("Actions") {
                ActionListEditor(project: coordinator.project, actions: slide.actions) { actions in
                    coordinator.setSlideActions(actions, slideID: slide.id, inPresentation: presentation.id)
                }
                Text("Run when the slide is taken live: start a timer, show a message or prop, change the stage display, run a macro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        section("Presenter Notes") {
            TextEditor(text: Binding(
                get: { slide.notes ?? "" },
                set: { coordinator.setNotes($0, slideID: slide.id, inPresentation: presentation.id) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(Spacing.sm)
            .frame(height: 110)
            .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: Radius.card))
            // The raised fill alone is nearly the inspector's colour in dark mode; the outline shows the field.
            .hairlineBorder(RoundedRectangle(cornerRadius: Radius.card))
            Text("Only you see these. The audience never does.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Arrange

    @ViewBuilder
    private func arrange(_ element: SlideElement, slide: SlideDocument) -> some View {
        section("Arrange") {
            if let frame = element.frame {
                Grid(alignment: .leading, horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
                    GridRow {
                        pointField("X", frame: frame, keyPath: \.x, axis: .horizontal, element: element, slide: slide)
                        pointField("Y", frame: frame, keyPath: \.y, axis: .vertical, element: element, slide: slide)
                    }
                    GridRow {
                        pointField("W", frame: frame, keyPath: \.width, axis: .horizontal, element: element, slide: slide)
                        pointField("H", frame: frame, keyPath: \.height, axis: .vertical, element: element, slide: slide)
                    }
                }
                Text("In slide points (1920 × 1080).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Drag the text on the slide to place it freely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.xs) {
                orderButton("Send to Back", systemImage: "arrow.down.to.line", .back, element: element, slide: slide)
                orderButton("Send Backward", systemImage: "arrow.down", .backward, element: element, slide: slide)
                orderButton("Bring Forward", systemImage: "arrow.up", .forward, element: element, slide: slide)
                orderButton("Bring to Front", systemImage: "arrow.up.to.line", .front, element: element, slide: slide)
                Spacer()
                Button(role: .destructive) {
                    coordinator.deleteElement(element.id, slideID: slide.id, inPresentation: presentation.id)
                    selectedElementID = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete (⌫)")
            }
        }
    }

    private func pointField(
        _ label: String,
        frame: NormalizedRect,
        keyPath: WritableKeyPath<NormalizedRect, Double>,
        axis: Axis,
        element: SlideElement,
        slide: SlideDocument
    ) -> some View {
        let points = axis == .horizontal ? SlideRenderView.canvasSize.width : SlideRenderView.canvasSize.height
        return HStack(spacing: Spacing.xs) {
            Text(label).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            TextField(label, value: Binding(
                get: { (frame[keyPath: keyPath] * points).rounded() },
                set: { value in
                    var updatedFrame = frame
                    updatedFrame[keyPath: keyPath] = value / points
                    var updated = element
                    updated.frame = updatedFrame.clampedToCanvas()
                    update(updated, on: slide)
                }
            ), format: .number.precision(.fractionLength(0)))
            .labelsHidden()
            .frame(width: 64)
        }
    }

    private func orderButton(
        _ title: String,
        systemImage: String,
        _ order: PresentationCoordinator.ElementOrder,
        element: SlideElement,
        slide: SlideDocument
    ) -> some View {
        Button {
            coordinator.reorderElement(element.id, order, slideID: slide.id, inPresentation: presentation.id)
        } label: {
            Image(systemName: systemImage)
        }
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: Animate

    @ViewBuilder
    private var animateTab: some View {
        if let slide {
            section("Transition") {
                Picker("Transition", selection: Binding<PresenterCore.SlideTransition.Kind?>(
                    get: { slide.transition?.kind },
                    set: { kind in
                        let transition = kind.map {
                            slide.transition?.with(kind: $0) ?? PresenterCore.SlideTransition(kind: $0, duration: 0.6)
                        }
                        coordinator.setTransition(transition, slideID: slide.id, inPresentation: presentation.id)
                    }
                )) {
                    Text("None").tag(PresenterCore.SlideTransition.Kind?.none)
                    ForEach(PresenterCore.SlideTransition.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .labelsHidden()
                .fixedSize()
                if let transition = slide.transition {
                    if transition.kind.hasEdge {
                        TransitionEdgePicker(edge: Binding(
                            get: { transition.edge ?? .left },
                            set: { coordinator.setTransition(transition.with(edge: $0), slideID: slide.id, inPresentation: presentation.id) }
                        ))
                    }
                    labeledSlider("Duration", value: Binding(
                        get: { transition.duration },
                        set: { coordinator.setTransition(transition.with(duration: $0), slideID: slide.id, inPresentation: presentation.id) }
                    ), in: PresenterCore.SlideTransition.durationRange, format: { String(format: "%.1f s", $0) })
                }
                Text("Plays on the audience output when this slide goes live. Clear and Blackout are always instant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply to All Slides…") { isConfirmingTransitionForAll = true }
            }
            .confirmationDialog("Use this transition for every slide in the presentation?",
                                isPresented: $isConfirmingTransitionForAll) {
                Button("Apply to All Slides") {
                    coordinator.applyTransitionToAllSlides(from: slide.id, inPresentation: presentation.id)
                }
            }
            section("Element Transitions") {
                if let element {
                    elementTransitionControls("In", phase: .in, element: element, slide: slide)
                    elementTransitionControls("Out", phase: .out, element: element, slide: slide)
                    Text("Play as the slide arrives and as it leaves. Everything else on the slide follows the slide's transition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select a text, shape or image on the slide to give it its own transition, for when the whole slide shouldn't move.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            placeholder("Select a slide to set its transition.")
        }
    }

    /// One element's In or Out transition: its kind (None follows the slide), direction, duration and, for In, delay.
    @ViewBuilder
    private func elementTransitionControls(_ title: String, phase: ElementPhase, element: SlideElement, slide: SlideDocument) -> some View {
        let transition = element[transition: phase]
        let set: (ElementTransition?) -> Void = {
            coordinator.setElementTransition($0, phase: phase, elementID: element.id, slideID: slide.id, inPresentation: presentation.id)
        }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Picker(title, selection: Binding<ElementTransition.Kind?>(
                    get: { transition?.kind },
                    set: { kind in
                        set(kind.map { kind in
                            var updated = transition ?? ElementTransition(kind: kind)
                            updated.kind = kind
                            return updated
                        })
                    }
                )) {
                    Text("None").tag(ElementTransition.Kind?.none)
                    ForEach(ElementTransition.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let transition {
                if transition.kind == .push || transition.kind == .wipe {
                    TransitionEdgePicker(edge: Binding(
                        get: { transition.edge },
                        set: { edge in
                            var updated = transition
                            updated.edge = edge
                            set(updated)
                        }
                    ), phase: phase)
                }
                labeledSlider("Duration", value: Binding(
                    get: { transition.duration },
                    set: { duration in
                        var updated = transition
                        updated.duration = duration
                        set(updated)
                    }
                ), in: ElementTransition.durationRange, format: { String(format: "%.1f s", $0) })
                if phase == .in {
                    labeledSlider("Delay", value: Binding(
                        get: { transition.delay },
                        set: { delay in
                            var updated = transition
                            updated.delay = (delay * 10).rounded() / 10
                            set(updated)
                        }
                    ), in: 0...5, format: { String(format: "%.1f s", $0) })
                }
            }
        }
    }

    // MARK: Document

    @ViewBuilder
    private var documentTab: some View {
        section("Presentation") {
            TextField("Title", text: Binding(
                get: { presentation.title },
                set: { coordinator.renamePresentation(presentation.id, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            Text(presentation.slides.count == 1 ? "1 slide" : "\(presentation.slides.count) slides")
                .foregroundStyle(.secondary)
        }
        // Props are overlays, not slides of a presentation: they don't follow a theme.
        if presentation.id != coordinator.project.props.id {
            themeSection
        }
        section("Background") {
            BackgroundInspector(coordinator: coordinator, target: .presentation(presentation.id))
            Text("Used by every slide that doesn't set its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if presentation.id != coordinator.project.props.id {
            section("Song") {
                SongDetailsFields(coordinator: coordinator, presentation: presentation)
                Text("Writers, copyright and CCLI number, for your licence reports. Filled in when a song is imported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Soundtrack") {
                SoundtrackControls(coordinator: coordinator, track: Binding(
                    get: { presentation.soundtrack },
                    set: { coordinator.setSoundtrack($0, presentationID: presentation.id) }
                ))
            }
        }
    }

    private var themeSection: some View {
        section("Theme") {
            Picker("Theme", selection: Binding(get: { presentation.themeID }, set: { choose($0) })) {
                Text("None").tag(UUID?.none)
                Divider()
                ForEach(coordinator.project.themes) { theme in
                    Text(theme.name.isEmpty ? "Untitled Theme" : theme.name).tag(Optional(theme.id))
                }
            }
            .labelsHidden()
            if let theme {
                Button("Edit Theme…") { editingThemeID = theme.id }
                Button("Revert All Text to Theme") {
                    coordinator.revertToTheme(elementID: nil, inPresentation: presentation.id)
                }
                .help("Text formatted by hand on any slide follows the theme again")
            }
            Text("Text follows the theme unless you format it by hand. Make or edit themes in the sidebar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            "Keep the formatting already on these slides?",
            isPresented: Binding(get: { pendingThemeID != nil }, set: { if !$0 { pendingThemeID = nil } }),
            presenting: pendingThemeID
        ) { themeID in
            Button("Keep Slide Formatting") {
                coordinator.setPresentationTheme(themeID, presentationID: presentation.id, keepSlideFormatting: true)
            }
            Button("Use the Theme for All Text") {
                coordinator.setPresentationTheme(themeID, presentationID: presentation.id, keepSlideFormatting: false)
            }
        } message: { _ in
            Text("Text you styled or placed by hand can keep its look, or take the theme's like the rest.")
        }
    }

    private func choose(_ themeID: UUID?) {
        guard themeID != presentation.themeID else { return }
        if themeID != nil, coordinator.hasOwnFormatting(presentation.id) {
            pendingThemeID = themeID
        } else {
            coordinator.setPresentationTheme(themeID, presentationID: presentation.id)
        }
    }

    // MARK: Building blocks

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider()
            Text(title).font(.subheadline.bold())
            content()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Spacing.xl)
    }

    private func labeledSlider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: @escaping (Double) -> String = { "\(Int($0))" }
    ) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Slider(value: value, in: range)
            Text(format(value.wrappedValue))
                .monospacedDigit()
                .frame(width: Widths.valueLabel, alignment: .trailing)
        }
    }

    /// A checkbox that turns a colour on or off, with a picker for it when on.
    private func optionalColor(
        _ label: String,
        color: RGBAColor?,
        defaultColor: RGBAColor,
        set: @escaping (RGBAColor?) -> Void
    ) -> some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { color != nil },
                set: { set($0 ? defaultColor : nil) }
            ))
            Spacer()
            if let color {
                ColorPicker(label, selection: Binding(
                    get: { color.color },
                    set: { set(RGBAColor($0)) }
                ), supportsOpacity: true)
                .labelsHidden()
            }
        }
    }

    private func update(_ element: SlideElement, on slide: SlideDocument) {
        coordinator.updateElement(element, slideID: slide.id, inPresentation: presentation.id)
    }

    private func replaceImage(_ image: ImageElement, slide: SlideDocument) {
        guard let url = EditorImageImport.chooseImage(message: "Choose a replacement image") else { return }
        importError = nil
        Task {
            do {
                let asset = try await mediaLibrary.importImage(at: url)
                coordinator.addMediaAsset(asset)
                var updated = image
                updated.assetID = asset.id
                update(.image(updated), on: slide)
            } catch {
                importError = "\(url.lastPathComponent) couldn't be imported."
            }
        }
    }
}

#if DEBUG
// At the inspector's narrowest width, with an image background so the widest Format rows show
// (docs/adr/0002-spacing-and-panel-padding.md). The image is missing on purpose; its warning wraps too.
private struct EditorInspectorPreview: View {
    let tab: EditorInspectorTab
    @State private var coordinator: PresentationCoordinator = {
        var project = ProjectDocument.sample()
        let assetID = UUID()
        project.presentations[0].slides[0].background = .image(ImageBackground(assetID: assetID, dimming: 0.2))
        return PresentationCoordinator(project: project)
    }()
    @State private var mediaLibrary = MediaLibrary(directory: .temporaryDirectory.appendingPathComponent("PresenterPreview"))

    var body: some View {
        let presentation = coordinator.project.presentations[0]
        EditorInspector(
            coordinator: coordinator,
            presentation: presentation,
            slide: presentation.slides.first,
            tab: tab,
            selectedElementID: .constant(nil)
        )
        .environment(mediaLibrary)
        .frame(width: Widths.editorInspector.min, height: 700)
    }
}

#Preview("Format, narrowest") { EditorInspectorPreview(tab: .format) }
#Preview("Animate, narrowest") { EditorInspectorPreview(tab: .animate) }
#Preview("Document, narrowest") { EditorInspectorPreview(tab: .document) }
#endif
