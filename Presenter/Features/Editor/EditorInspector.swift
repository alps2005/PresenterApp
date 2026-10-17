import SwiftUI
import PresenterCore

/// The slide editor's right column. Format shows the selected element's settings (or the slide's when
/// nothing is selected), Animate the slide's transition, and Document the presentation's settings.
struct EditorInspector: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument
    let slide: SlideDocument?
    let tab: EditorInspectorTab
    @Binding var selectedElementID: UUID?

    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var isConfirmingTransitionForAll = false
    @State private var importError: String?

    private var element: SlideElement? {
        guard let selectedElementID else { return nil }
        return slide?.element(withID: selectedElementID)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .solidPanel(Palette.sidebar)
        .hardScrollEdges()
        .controlSize(.small)
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
        arrange(.text(text), slide: slide)
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
                Picker("Transition", selection: Binding(
                    get: { slide.transition == nil ? 0 : 1 },
                    set: { choice in
                        let transition: PresenterCore.SlideTransition? = choice == 0 ? nil : .dissolve(duration: slide.transition?.duration ?? 0.6)
                        coordinator.setTransition(transition, slideID: slide.id, inPresentation: presentation.id)
                    }
                )) {
                    Text("None").tag(0)
                    Text("Dissolve").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if let transition = slide.transition {
                    labeledSlider("Duration", value: Binding(
                        get: { transition.duration },
                        set: { coordinator.setTransition(.dissolve(duration: $0), slideID: slide.id, inPresentation: presentation.id) }
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
            section("Build In & Build Out") {
                comingSoon("Animating text and shapes onto and off a slide is coming in the next phase.")
            }
        } else {
            placeholder("Select a slide to set its transition.")
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
        section("Background") {
            BackgroundInspector(coordinator: coordinator, target: .presentation(presentation.id))
            Text("Used by every slide that doesn't set its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        section("Audio") {
            comingSoon("A soundtrack and audio cues for this presentation are coming in the next phase.")
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

    private func comingSoon(_ text: String) -> some View {
        Label(text, systemImage: "clock")
            .foregroundStyle(.secondary)
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
