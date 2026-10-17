import AppKit
import SwiftUI
import PresenterCore
import UniformTypeIdentifiers

/// Which presentation the slide editor is open on, and the playlist entry it was opened from
/// (Take Live needs it). Props have no playlist entry, so nothing in them can be sent live.
struct EditSession: Equatable {
    let itemID: UUID?
    let presentationID: UUID
    var initialSlideID: UUID?
}

enum EditorInspectorTab: Hashable {
    case format
    case animate
    case document
}

enum EditorZoom: Hashable {
    case fit
    case percent(Int)

    static let presets = [25, 50, 75, 100, 150, 200]

    var label: String {
        switch self {
        case .fit: "Fit"
        case .percent(let percent): "\(percent)%"
        }
    }

    /// Canvas points per slide point, or nil to fit the window.
    var scale: CGFloat? {
        switch self {
        case .fit: nil
        case .percent(let percent): CGFloat(percent) / 100
        }
    }
}

/// The Keynote-style slide editor: slide thumbnails on the left, the slide canvas in the middle, and an
/// inspector on the right whose content follows the toolbar's Format / Animate / Document buttons.
/// It edits the project only; the audience output changes when a slide is taken live.
struct PresentationEditor: View {
    let coordinator: PresentationCoordinator
    let session: EditSession
    let onDone: () -> Void

    @Environment(MediaLibrary.self) private var mediaLibrary
    @State private var selectedSlideID: UUID?
    @State private var selectedElementID: UUID?
    @State private var inspectorTab: EditorInspectorTab = .format
    @State private var isInspectorPresented = true
    @State private var zoom: EditorZoom = .fit
    @State private var importError: String?
    @State private var isReflowing = false

    private var presentation: PresentationDocument? {
        coordinator.project.presentation(withID: session.presentationID)
    }

    private var slide: SlideDocument? {
        guard let selectedSlideID else { return nil }
        return presentation?.slide(withID: selectedSlideID)
    }

    var body: some View {
        if let presentation, session.itemID.map({ coordinator.project.playlist.item(withID: $0) != nil }) ?? true {
            editor(presentation)
        } else {
            // The presentation left the playlist while it was being edited.
            Color.clear.onAppear { onDone() }
        }
    }

    private var inspectorIdealWidth: CGFloat {
        #if DEBUG
        // `-PresenterDebugInspectorWidth 270` opens the inspector at its narrowest, where rows overflow first.
        let width = UserDefaults.standard.double(forKey: "PresenterDebugInspectorWidth")
        if width > 0 { return width }
        #endif
        return Widths.editorInspector.ideal
    }

    private func editor(_ presentation: PresentationDocument) -> some View {
        NavigationSplitView {
            SlideThumbnailSidebar(
                coordinator: coordinator,
                presentation: presentation,
                itemID: session.itemID,
                selection: $selectedSlideID,
                onAddSlide: { addSlide() }
            )
            .navigationSplitViewColumnWidth(
                min: Widths.editorThumbnails.min, ideal: Widths.editorThumbnails.ideal, max: Widths.editorThumbnails.max
            )
        } detail: {
            Group {
                if let slide {
                    EditorCanvas(
                        coordinator: coordinator,
                        presentation: presentation,
                        slide: slide,
                        selectedElementID: $selectedElementID,
                        zoom: zoom,
                        onExit: { onDone() }
                    )
                } else {
                    ContentUnavailableView(
                        "No Slide Selected",
                        systemImage: "rectangle",
                        description: Text("Select a slide on the left, or add one.")
                    )
                }
            }
            .inspector(isPresented: $isInspectorPresented) {
                EditorInspector(
                    coordinator: coordinator,
                    presentation: presentation,
                    slide: slide,
                    tab: inspectorTab,
                    selectedElementID: $selectedElementID
                )
                .inspectorColumnWidth(
                    min: Widths.editorInspector.min, ideal: inspectorIdealWidth, max: Widths.editorInspector.max
                )
            }
        }
        .navigationTitle(presentation.title.isEmpty ? "Untitled" : presentation.title)
        .toolbar { toolbar }
        .solidToolbar()
        .onAppear {
            selectedSlideID = session.initialSlideID ?? presentation.slides.first?.id
            #if DEBUG
            // `-PresenterDebugEditorTab format|animate|document`, for scripts/layout-screenshots.sh.
            switch UserDefaults.standard.string(forKey: "PresenterDebugEditorTab") {
            case "animate": inspectorTab = .animate
            case "document": inspectorTab = .document
            default: break
            }
            #endif
        }
        // Keep a valid slide selected when the selected one is deleted.
        .onChange(of: presentation.slides.map(\.id)) { old, new in
            guard let selected = selectedSlideID, !new.contains(selected) else { return }
            let oldIndex = old.firstIndex(of: selected) ?? 0
            selectedSlideID = new.isEmpty ? nil : new[min(oldIndex, new.count - 1)]
        }
        // Like Keynote, a slide is always selected: clicking empty space in the thumbnail list keeps the current one.
        .onChange(of: selectedSlideID) { old, new in
            selectedElementID = nil
            if new == nil, let old, presentation.slide(withID: old) != nil {
                selectedSlideID = old
            }
        }
        .sheet(isPresented: $isReflowing) {
            ReflowSheet(coordinator: coordinator, presentationID: session.presentationID)
        }
        .alert("Couldn't Add the Image", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { onDone() } label: {
                Label("Done", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            }
            .help("Leave the editor and return to the show (Esc)")
        }

        ToolbarItemGroup(placement: .principal) {
            Button { takeLive() } label: {
                Label("Take Live", systemImage: "play.fill")
            }
            .help(session.itemID == nil ? "Props are shown from Show Controls, not sent live" : "Take this slide live on the audience output")
            .disabled(slide == nil || session.itemID == nil)

            Button { addSlide() } label: {
                Label("Add Slide", systemImage: "plus.rectangle")
            }
            .help("Add a blank slide after this one")

            Button { isReflowing = true } label: {
                Label("Reflow", systemImage: "text.alignleft")
            }
            .help("Edit all of this presentation's words as one document")

            Button { addText() } label: {
                Label("Text", systemImage: "character.textbox")
            }
            .help("Add a text box")
            .disabled(slide == nil)

            Menu {
                Button("Rectangle") { addShape(.rectangle) }
                Button("Rounded Rectangle") { addShape(.roundedRectangle) }
                Button("Oval") { addShape(.ellipse) }
            } label: {
                Label("Shape", systemImage: "square.on.circle")
            }
            .help("Add a shape")
            .disabled(slide == nil)

            Button { addImage() } label: {
                Label("Media", systemImage: "paperclip")
            }
            .help("Add an image to the slide")
            .disabled(slide == nil)

            Menu {
                Button("Fit") { zoom = .fit }
                Divider()
                ForEach(EditorZoom.presets, id: \.self) { percent in
                    Button("\(percent)%") { zoom = .percent(percent) }
                }
            } label: {
                Text(zoom.label)
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help("Zoom")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            inspectorToggle(.format, title: "Format", systemImage: "paintbrush")
            inspectorToggle(.animate, title: "Animate", systemImage: "diamond")
            inspectorToggle(.document, title: "Document", systemImage: "doc.text")
        }
    }

    /// Like Keynote: pressing a tab's button shows its panel; pressing the active one hides the inspector.
    private func inspectorToggle(_ tab: EditorInspectorTab, title: String, systemImage: String) -> some View {
        Toggle(isOn: Binding(
            get: { isInspectorPresented && inspectorTab == tab },
            set: { isOn in
                if isOn {
                    inspectorTab = tab
                    isInspectorPresented = true
                } else {
                    isInspectorPresented = false
                }
            }
        )) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .help(title)
    }

    // MARK: Actions

    private func takeLive() {
        guard let slide else { return }
        guard let itemID = session.itemID else { return }
        coordinator.takeLive(slideID: slide.id, inItem: itemID)
    }

    private func addSlide() {
        if let inserted = coordinator.insertSlide(after: selectedSlideID, inPresentation: session.presentationID) {
            selectedSlideID = inserted.id
        }
    }

    private func addText() {
        var text = TextElement(text: "Text", box: TextBox(frame: .centered(width: 0.5, height: 0.2)))
        text.style.fontSize = 72
        add(.text(text))
    }

    private func addShape(_ kind: ShapeElement.Kind) {
        // Square on the 16:9 canvas: the same size in points on both axes.
        add(.shape(ShapeElement(kind: kind, frame: .centered(width: 0.2, height: 0.2 * 16 / 9))))
    }

    private func addImage() {
        guard let url = EditorImageImport.chooseImage(message: "Choose an image to add to the slide") else { return }
        Task {
            do {
                let asset = try await mediaLibrary.importImage(at: url)
                coordinator.addMediaAsset(asset)
                add(.image(ImageElement(assetID: asset.id, frame: EditorImageImport.frame(for: asset))))
            } catch {
                importError = "\(url.lastPathComponent) couldn't be imported. Choose a JPEG, PNG, HEIC or other image file."
            }
        }
    }

    private func add(_ element: SlideElement) {
        guard let slide else { return }
        guard coordinator.addElement(element, toSlide: slide.id, inPresentation: session.presentationID).isApplied else { return }
        selectedElementID = element.id
        inspectorTab = .format
        isInspectorPresented = true
    }
}

/// Picking an image file and sizing it for the canvas, shared by the toolbar and the image inspector.
enum EditorImageImport {
    static func chooseImage(message: String) -> URL? {
        MediaPanel.choose([.image], message: message).first
    }

    /// A centred frame with the image's aspect ratio, at most 40% of the canvas wide and 60% high.
    static func frame(for asset: MediaAsset) -> NormalizedRect {
        let canvas = SlideRenderView.canvasSize
        let aspect = Double(asset.pixelWidth) / Double(max(asset.pixelHeight, 1))
        var width = 0.4
        var height = width * canvas.width / canvas.height / aspect
        if height > 0.6 {
            height = 0.6
            width = height * aspect * canvas.height / canvas.width
        }
        return .centered(width: width, height: height)
    }
}
