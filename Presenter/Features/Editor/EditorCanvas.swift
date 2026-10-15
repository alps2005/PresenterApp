import AppKit
import SwiftUI
import PresenterCore
import UniformTypeIdentifiers

/// The slide being edited, drawn with the shared renderer, with selection, dragging, resizing and in-place
/// text editing layered on top. Drags update a local draft and commit once when they end, so autosave and
/// the live "edited" warning aren't triggered on every frame.
struct EditorCanvas: View {
    let coordinator: PresentationCoordinator
    let presentation: PresentationDocument
    let slide: SlideDocument
    @Binding var selectedElementID: UUID?
    let zoom: EditorZoom
    /// Esc with nothing selected leaves the editor.
    let onExit: () -> Void

    private struct Draft {
        let elementID: UUID
        var frame: NormalizedRect
    }

    /// An element the operator can click: its frame, or for text without a box, the area it flows in.
    private struct Target: Identifiable {
        let element: SlideElement
        let frame: NormalizedRect
        var id: UUID { element.id }
    }

    @State private var draft: Draft?
    /// The element's frame when the current drag began.
    @State private var dragOrigin: NormalizedRect?
    /// Alignment guides lit up by the current drag, and the position/size readout shown beside the element.
    @State private var guides: Snapping.Result?
    @State private var readout: String?
    @State private var editingTextID: UUID?
    @State private var editingText = ""
    @FocusState private var isCanvasFocused: Bool
    @FocusState private var isTextFocused: Bool

    /// Drags are measured in the stage's coordinates, which don't move. Measuring in the dragged element's own
    /// coordinates (the default) fed each frame's movement back into the next and made the element lag and jitter.
    static let stageSpace = "editorStage"
    private static let backspace = KeyEquivalent("\u{7F}")
    private static let padding: CGFloat = 40
    private static let canvasSize = SlideRenderView.canvasSize
    private static let minimumSize = 0.02
    private static let nudge = 1.0 / 192
    /// How close, in screen points, an edge or centre must come to a guide before it snaps, at any zoom.
    private static let snapDistance: CGFloat = 6
    /// Keynote's alignment-guide yellow.
    private static let guideColor = Color(red: 0.98, green: 0.76, blue: 0.0)

    var body: some View {
        GeometryReader { geometry in
            let fit = max(0.05, min(
                (geometry.size.width - 2 * Self.padding) / Self.canvasSize.width,
                (geometry.size.height - 2 * Self.padding) / Self.canvasSize.height
            ))
            ScrollView([.horizontal, .vertical]) {
                stage(scale: zoom.scale ?? fit)
                    .padding(Self.padding)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .scrollIndicators(zoom == .fit ? .hidden : .automatic)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focused($isCanvasFocused)
        .focusEffectDisabled()
        // While text is being typed, keys belong to the text editor, not to these shortcuts.
        // The Mac's Delete key (⌫) sends U+007F, which isn't SwiftUI's `.delete` (U+0008), so match it too.
        .onKeyPress(keys: [.delete, .deleteForward, Self.backspace]) { _ in
            guard editingTextID == nil, selectedElementID != nil else { return .ignored }
            deleteSelection()
            return .handled
        }
        // Edit menu: Copy, Cut, Paste and Delete act on the selected element. While text is being typed, the
        // text editor has focus and handles them itself.
        .onCopyCommand { copySelection() }
        .onCutCommand {
            let providers = copySelection()
            if !providers.isEmpty { deleteSelection() }
            return providers
        }
        .onPasteCommand(of: [.json, .plainText]) { _ in pasteFromPasteboard() }
        .onDeleteCommand { deleteSelection() }
        .focusedValue(\.editorElementActions, editingTextID == nil && selectedElementID != nil
            ? EditorElementActions(duplicate: { duplicateSelection() })
            : nil)
        .onKeyPress(.escape) {
            if editingTextID != nil {
                endTextEditing()
            } else if selectedElementID != nil {
                selectedElementID = nil
            } else {
                onExit()
            }
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            guard editingTextID == nil, let target = selectedTarget else { return .ignored }
            let step = press.modifiers.contains(.shift) ? Self.nudge * 10 : Self.nudge
            var frame = target.frame
            switch press.key {
            case .upArrow: frame.y -= step * Self.canvasSize.width / Self.canvasSize.height
            case .downArrow: frame.y += step * Self.canvasSize.width / Self.canvasSize.height
            case .leftArrow: frame.x -= step
            default: frame.x += step
            }
            commit(frame: frame.clampedToCanvas(), for: target.element)
            return .handled
        }
        .onChange(of: slide.id) {
            endTextEditing()
            draft = nil
            dragOrigin = nil
        }
        .onAppear { isCanvasFocused = true }
    }

    // MARK: Stage

    private func stage(scale: CGFloat) -> some View {
        let size = CGSize(width: Self.canvasSize.width * scale, height: Self.canvasSize.height * scale)
        let shown = displayedSlide
        let targets = Self.targets(in: shown)
        let selectedTarget = selectedElementID.flatMap { id in targets.first { $0.id == id } }
        return ZStack(alignment: .topLeading) {
            SlideRenderView(scene: .slide(presentation.rendered(shown)))
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { select(nil) }

            ForEach(targets) { target in
                if target.id != editingTextID {
                    hitArea(for: target, stageSize: size)
                }
            }

            if let guides {
                guideLines(guides, stageSize: size)
            }

            if let target = selectedTarget, target.id != editingTextID {
                SelectionChrome(rect: stageRect(target.frame, size: size)) { handle, translation, ended in
                    resize(target, handle: handle, translation: translation, stageSize: size, ended: ended)
                }
            }

            if let editingTextID, let target = targets.first(where: { $0.id == editingTextID }),
               case .text(let text) = target.element {
                inlineTextEditor(text: text, rect: stageRect(target.frame, size: size), scale: scale)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if let readout, let draft {
                readoutTag(readout, near: stageRect(draft.frame, size: size), stageSize: size)
            }
        }
        .coordinateSpace(name: Self.stageSpace)
        .clipped()
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private func hitArea(for target: Target, stageSize: CGSize) -> some View {
        let rect = stageRect(target.frame, size: stageSize)
        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.stageSpace))
                    .onChanged { value in move(target, translation: value.translation, stageSize: stageSize) }
                    .onEnded { _ in commitDraft() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginTextEditing(target) })
            .simultaneousGesture(TapGesture().onEnded { select(target.id) })
            .offset(x: rect.minX, y: rect.minY)
            .help(target.element.helpText)
    }

    private func inlineTextEditor(text: TextElement, rect: CGRect, scale: CGFloat) -> some View {
        var style = text.style
        style.fontSize *= scale
        return TextEditor(text: $editingText)
            .font(style.font)
            .lineSpacing(text.style.lineSpacing * scale)
            .multilineTextAlignment(text.style.alignment.textAlignment)
            .foregroundStyle(text.style.color.color)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.2))
            .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1) }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .focused($isTextFocused)
            .onAppear { isTextFocused = true }
            .onChange(of: isTextFocused) { _, focused in
                if !focused { endTextEditing() }
            }
    }

    // MARK: Model of what's shown

    /// The slide as drawn right now: the in-progress drag applied, and the text being typed hidden
    /// (the editor shows it instead).
    private var displayedSlide: SlideDocument {
        var shown = slide
        for index in shown.elements.indices {
            if let draft, shown.elements[index].id == draft.elementID {
                shown.elements[index].frame = draft.frame
            }
            if shown.elements[index].id == editingTextID, case .text(var text) = shown.elements[index] {
                text.text = ""
                shown.elements[index] = .text(text)
            }
        }
        return shown
    }

    /// Clickable elements, bottom to top. Text without a box has no frame of its own; it gets the slice of the
    /// centred flow area it roughly occupies, and a real box the first time it's moved or resized.
    private static func targets(in shown: SlideDocument) -> [Target] {
        let flow = shown.elements.filter { $0.frame == nil }
        let flowArea = NormalizedRect(
            x: 120 / Self.canvasSize.width,
            y: 120 / Self.canvasSize.height,
            width: 1 - 240 / Self.canvasSize.width,
            height: 1 - 240 / Self.canvasSize.height
        )
        let flowTargets = flow.enumerated().map { index, element in
            let slice = flowArea.height / Double(flow.count)
            return Target(element: element, frame: NormalizedRect(
                x: flowArea.x, y: flowArea.y + Double(index) * slice, width: flowArea.width, height: slice
            ))
        }
        let framed = shown.elements.compactMap { element in element.frame.map { Target(element: element, frame: $0) } }
        return flowTargets + framed
    }

    private var selectedTarget: Target? {
        guard let selectedElementID else { return nil }
        return Self.targets(in: displayedSlide).first { $0.id == selectedElementID }
    }

    private func stageRect(_ frame: NormalizedRect, size: CGSize) -> CGRect {
        CGRect(x: frame.x * size.width, y: frame.y * size.height, width: frame.width * size.width, height: frame.height * size.height)
    }

    // MARK: Interaction

    private func select(_ elementID: UUID?) {
        if editingTextID != nil, editingTextID != elementID { endTextEditing() }
        selectedElementID = elementID
        isCanvasFocused = true
    }

    private func move(_ target: Target, translation: CGSize, stageSize: CGSize) {
        guard editingTextID == nil else { return }
        if dragOrigin == nil {
            dragOrigin = target.frame
            select(target.id)
        }
        guard let origin = dragOrigin else { return }
        var frame = origin
        frame.x += translation.width / stageSize.width
        frame.y += translation.height / stageSize.height
        frame = frame.clampedToCanvas()
        // Hold ⌘ to place freely, like Keynote.
        if Self.isSnappingSuspended {
            guides = nil
        } else {
            let result = Snapping.move(frame, among: otherFrames(than: target.id), tolerance: snapTolerance(stageSize))
            frame = result.frame.clampedToCanvas()
            guides = result
        }
        draft = Draft(elementID: target.id, frame: frame)
        readout = "x: \(Int((frame.x * Self.canvasSize.width).rounded())) pt  y: \(Int((frame.y * Self.canvasSize.height).rounded())) pt"
    }

    private func resize(_ target: Target, handle: SelectionChrome.Handle, translation: CGSize, stageSize: CGSize, ended: Bool) {
        if dragOrigin == nil { dragOrigin = target.frame }
        guard let origin = dragOrigin else { return }
        let edges = Snapping.Edges(left: handle.movesLeft, right: handle.movesRight, top: handle.movesTop, bottom: handle.movesBottom)
        var frame = Snapping.resized(origin, moving: edges, by: translation.width / stageSize.width,
                                     translation.height / stageSize.height, minimumSize: Self.minimumSize)
        if Self.isSnappingSuspended {
            guides = nil
        } else {
            let result = Snapping.resize(frame, moving: edges, among: otherFrames(than: target.id),
                                         tolerance: snapTolerance(stageSize), minimumSize: Self.minimumSize)
            frame = result.frame
            guides = result
        }
        draft = Draft(elementID: target.id, frame: frame)
        readout = "w: \(Int((frame.width * Self.canvasSize.width).rounded())) pt  h: \(Int((frame.height * Self.canvasSize.height).rounded())) pt"
        if ended { commitDraft() }
    }

    private func commitDraft() {
        defer {
            draft = nil
            dragOrigin = nil
            guides = nil
            readout = nil
        }
        guard let draft, let element = slide.element(withID: draft.elementID) else { return }
        commit(frame: draft.frame, for: element)
    }

    // MARK: Alignment guides

    private static var isSnappingSuspended: Bool {
        NSEvent.modifierFlags.contains(.command)
    }

    /// The snap distance in unit coordinates, so it feels the same at every zoom level.
    private func snapTolerance(_ stageSize: CGSize) -> (x: Double, y: Double) {
        (x: Self.snapDistance / stageSize.width, y: Self.snapDistance / stageSize.height)
    }

    /// Frames of the slide's other placed elements. Text without a box has no real frame, so it isn't a guide.
    private func otherFrames(than elementID: UUID) -> [NormalizedRect] {
        slide.elements.compactMap { $0.id == elementID ? nil : $0.frame }
    }

    private func guideLines(_ guides: Snapping.Result, stageSize: CGSize) -> some View {
        Path { path in
            for x in guides.verticalGuides {
                let position = (x * stageSize.width).rounded() + 0.5
                path.move(to: CGPoint(x: position, y: 0))
                path.addLine(to: CGPoint(x: position, y: stageSize.height))
            }
            for y in guides.horizontalGuides {
                let position = (y * stageSize.height).rounded() + 0.5
                path.move(to: CGPoint(x: 0, y: position))
                path.addLine(to: CGPoint(x: stageSize.width, y: position))
            }
        }
        .stroke(Self.guideColor, lineWidth: 1)
        .allowsHitTesting(false)
    }

    /// A small dark tag beside the element's top-right corner, kept inside the slide.
    private func readoutTag(_ text: String, near rect: CGRect, stageSize: CGSize) -> some View {
        let tagSize = CGSize(width: 150, height: 24)
        let x = min(max(rect.maxX + 10, 4), stageSize.width - tagSize.width - 4)
        let y = min(max(rect.minY, 4), stageSize.height - tagSize.height - 4)
        return Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: tagSize.height)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    private func commit(frame: NormalizedRect, for element: SlideElement) {
        var element = element
        element.frame = frame
        coordinator.updateElement(element, slideID: slide.id, inPresentation: presentation.id)
    }

    private func beginTextEditing(_ target: Target) {
        guard case .text(let text) = target.element else { return }
        selectedElementID = text.id
        editingText = text.text
        editingTextID = text.id
    }

    private func endTextEditing() {
        guard let editingTextID else { return }
        self.editingTextID = nil
        if case .text(var text) = slide.element(withID: editingTextID), text.text != editingText {
            text.text = editingText
            coordinator.updateElement(.text(text), slideID: slide.id, inPresentation: presentation.id)
        }
        isCanvasFocused = true
    }
}

// MARK: - Clipboard and duplicate

extension EditorCanvas {
    /// What Copy puts on the pasteboard: the element as JSON, plus its words as plain text for other apps.
    private struct ElementClipboard: Codable {
        let presenterElements: [SlideElement]
    }

    private static let clipboardType = NSPasteboard.PasteboardType(UTType.json.identifier)

    private func copySelection() -> [NSItemProvider] {
        guard editingTextID == nil, let selectedElementID, let element = slide.element(withID: selectedElementID),
              let data = try? JSONEncoder().encode(ElementClipboard(presenterElements: [element])) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: .json, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        if case .text(let text) = element {
            provider.registerObject(text.text as NSString, visibility: .all)
        }
        return [provider]
    }

    /// Pastes copied elements, or text copied from another app as a new text box.
    private func pasteFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: Self.clipboardType),
           let clipboard = try? JSONDecoder().decode(ElementClipboard.self, from: data) {
            insert(clipboard.presenterElements)
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            var text = TextElement(text: string, box: TextBox(frame: .centered(width: 0.6, height: 0.25)))
            text.style.fontSize = 72
            insert([.text(text)])
        }
    }

    /// Adds copies with new identities. Like Keynote, a copy that would land exactly on an element already on
    /// the slide is nudged down and to the right instead.
    private func insert(_ elements: [SlideElement]) {
        var pastedID: UUID?
        for element in elements {
            let occupied = (coordinator.project.presentation(withID: presentation.id)?.slide(withID: slide.id)?.elements ?? [])
                .compactMap(\.frame)
            let copy = element.pastedCopy(avoiding: occupied, offset: PresentationCoordinator.duplicateOffset)
            // An image from another project whose file isn't in this one is skipped (rejected as unknown media).
            if coordinator.addElement(copy, toSlide: slide.id, inPresentation: presentation.id).isApplied {
                pastedID = copy.id
            }
        }
        if let pastedID {
            selectedElementID = pastedID
            isCanvasFocused = true
        }
    }

    private func duplicateSelection() {
        guard editingTextID == nil, let selectedElementID,
              let copy = coordinator.duplicateElement(selectedElementID, slideID: slide.id, inPresentation: presentation.id)
        else { return }
        self.selectedElementID = copy.id
    }

    private func deleteSelection() {
        guard editingTextID == nil, let selectedElementID else { return }
        coordinator.deleteElement(selectedElementID, slideID: slide.id, inPresentation: presentation.id)
        self.selectedElementID = nil
    }
}

/// Edit › Duplicate (⌘D) reaches the focused editor canvas through this.
struct EditorElementActions {
    let duplicate: () -> Void
}

private struct EditorElementActionsKey: FocusedValueKey {
    typealias Value = EditorElementActions
}

extension FocusedValues {
    var editorElementActions: EditorElementActions? {
        get { self[EditorElementActionsKey.self] }
        set { self[EditorElementActionsKey.self] = newValue }
    }
}

/// The selection outline and its eight resize handles, drawn in screen points so handles keep their size at any zoom.
struct SelectionChrome: View {
    enum Handle: CaseIterable {
        case topLeading, top, topTrailing, trailing, bottomTrailing, bottom, bottomLeading, leading

        /// Where the handle sits on the outline, in unit coordinates.
        var anchor: UnitPoint {
            switch self {
            case .topLeading: .topLeading
            case .top: .top
            case .topTrailing: .topTrailing
            case .trailing: .trailing
            case .bottomTrailing: .bottomTrailing
            case .bottom: .bottom
            case .bottomLeading: .bottomLeading
            case .leading: .leading
            }
        }

        var movesLeft: Bool { [.topLeading, .leading, .bottomLeading].contains(self) }
        var movesRight: Bool { [.topTrailing, .trailing, .bottomTrailing].contains(self) }
        var movesTop: Bool { [.topLeading, .top, .topTrailing].contains(self) }
        var movesBottom: Bool { [.bottomLeading, .bottom, .bottomTrailing].contains(self) }
    }

    let rect: CGRect
    /// Called while a handle is dragged, and once more with `ended` true when it's released.
    let onResize: (Handle, CGSize, Bool) -> Void

    private static let handleSize: CGFloat = 9

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

            ForEach(Handle.allCases, id: \.self) { handle in
                Rectangle()
                    .fill(Color.white)
                    .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                    .frame(width: Self.handleSize, height: Self.handleSize)
                    .contentShape(Rectangle().inset(by: -4))
                    .offset(
                        x: rect.minX + handle.anchor.x * rect.width - Self.handleSize / 2,
                        y: rect.minY + handle.anchor.y * rect.height - Self.handleSize / 2
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(EditorCanvas.stageSpace))
                            .onChanged { value in onResize(handle, value.translation, false) }
                            .onEnded { value in onResize(handle, value.translation, true) }
                    )
            }
        }
    }
}

private extension SlideElement {
    var helpText: String {
        switch self {
        case .text: "Text: drag to move, double-click to edit"
        case .shape: "Shape: drag to move"
        case .image: "Image: drag to move"
        }
    }
}
