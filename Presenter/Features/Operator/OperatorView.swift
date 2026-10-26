import SwiftUI
import PresenterCore
import UniformTypeIdentifiers

/// The operator's main window: playlist, slides, live state and controls.
struct OperatorView: View {
    /// The window can't shrink below this. Even with the sidebar at its widest, the workspace and
    /// live panel still get their minimum widths, so nothing is clipped.
    static let minimumWindowSize = CGSize(
        width: Widths.operatorSidebar.max + Widths.workspaceMinWidth + Widths.livePanelWidths.lowerBound + 20,
        height: 700
    )

    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let persistence: ProjectPersistence
    @Bindable var ui: OperatorUIState
    @Environment(MediaLibrary.self) private var mediaLibrary
    /// "Importing page 3 of 12…" while a PDF's pages are imported.
    @State private var pdfImportStatus: String?
    @State private var pdfImportProblem: String?
    /// A sidebar click asks the workspace to scroll to that item.
    @State private var scrollRequest: UUID?
    /// A library presentation clicked in the sidebar, shown in place of the show's slides.
    @State private var browsedPresentationID: UUID?
    /// Set while the slide editor is open; it then fills the window in place of the show view.
    @State private var editSession: EditSession?
    @AppStorage("quickEditVisible") private var isQuickEditVisible = false
    @AppStorage("mediaBinVisible") private var isMediaBinVisible = false
    @AppStorage("audioBinVisible") private var isAudioBinVisible = false
    /// Off by default: the console is dark for booths. View › Follow System Appearance turns it on.
    @AppStorage(PresenterCommands.followSystemAppearanceKey) private var followsSystemAppearance = false

    var body: some View {
        Group {
            if let editSession {
                PresentationEditor(coordinator: coordinator, session: editSession, onDone: { self.editSession = nil })
            } else {
                showView
            }
        }
        .preferredColorScheme(followsSystemAppearance ? nil : .dark)
        .background(WindowScreenReader { outputManager.operatorWindowMoved(to: $0) })
        #if DEBUG
        .onAppear { openEditorIfAsked() }
        #endif
        .onAppear {
            ui.isOperatorWindowOpen = true
            ui.hasShownOperatorWindow = true
        }
        // Once per launch, after the outputs have had a moment to come back on their screens; only if something's wrong.
        .task {
            guard !ui.hasRunLaunchCheck else { return }
            ui.hasRunLaunchCheck = true
            try? await Task.sleep(for: .seconds(2))
            if !PreServiceCheckSheet.problems(coordinator, outputManager, mediaLibrary, mode: .launch).isEmpty,
               ui.preServiceCheck == nil {
                ui.preServiceCheck = .launch
            }
        }
        .onDisappear { ui.isOperatorWindowOpen = false }
        // Opened from the welcome window, or the open show deleted: leave whatever belonged to the old show.
        .onChange(of: coordinator.project.activePlaylistID) {
            browsedPresentationID = nil
            editSession = nil
        }
        .sheet(isPresented: $ui.isShowingShows) {
            ShowsSheet(coordinator: coordinator) {
                browsedPresentationID = nil
                editSession = nil
            }
        }
        .sheet(isPresented: Binding(get: { ui.editingLookRole != nil }, set: { if !$0 { ui.editingLookRole = nil } })) {
            if let role = ui.editingLookRole {
                OutputLookSheet(coordinator: coordinator, outputManager: outputManager, role: role)
            }
        }
        .sheet(item: $ui.preServiceCheck) { mode in
            PreServiceCheckSheet(coordinator: coordinator, outputManager: outputManager, mode: mode) { itemID in
                browsedPresentationID = nil
                editSession = nil
                coordinator.selectItem(itemID)
                scrollRequest = itemID
            }
        }
        .onChange(of: ui.isImportingPDF) { _, isImporting in
            guard isImporting else { return }
            ui.isImportingPDF = false
            importPDF()
        }
        .sheet(isPresented: Binding(get: { pdfImportStatus != nil }, set: { _ in })) {
            HStack(spacing: Spacing.md) {
                ProgressView().controlSize(.small)
                Text(pdfImportStatus ?? "")
            }
            .padding(Spacing.xl)
            .interactiveDismissDisabled()
        }
        .alert("Import PDF", isPresented: Binding(
            get: { pdfImportProblem != nil },
            set: { if !$0 { pdfImportProblem = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(pdfImportProblem ?? "")
        }
        .sheet(isPresented: $ui.isShowingCCLIReport) {
            CCLIReportSheet(coordinator: coordinator)
        }
        .sheet(isPresented: $ui.isAddingSong) {
            NewSongSheet(coordinator: coordinator) { item in scrollRequest = item.id }
        }
        .sheet(isPresented: $ui.isImportingSongs) {
            ImportSongsSheet(coordinator: coordinator) { item in scrollRequest = item.id }
        }
        .sheet(isPresented: $ui.isAddingScripture) {
            ScriptureSheet(coordinator: coordinator) { item in scrollRequest = item.id }
        }
        .sheet(isPresented: Binding(get: { persistence.activity != nil }, set: { _ in })) {
            HStack(spacing: Spacing.md) {
                ProgressView().controlSize(.small)
                Text(persistence.activity ?? "")
            }
            .padding(Spacing.xl)
            .interactiveDismissDisabled()
        }
        .alert("Project", isPresented: Binding(
            get: { persistence.problem != nil },
            set: { if !$0 { persistence.problem = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(persistence.problem ?? "")
        }
    }

    /// Turns a PDF's pages into a presentation, one picture per slide, added to the show. Keynote and PowerPoint decks
    /// come in this way after File › Export To › PDF.
    private func importPDF() {
        guard let url = MediaPanel.choose([.pdf], message: "Choose a PDF. Export a Keynote or PowerPoint deck as a PDF first.").first
        else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDF-\(UUID().uuidString)", isDirectory: true)
        let title = url.deletingPathExtension().lastPathComponent
        pdfImportStatus = "Reading “\(title)”…"
        Task {
            defer {
                pdfImportStatus = nil
                try? FileManager.default.removeItem(at: folder)
            }
            do {
                let pages = try await Task.detached(priority: .userInitiated) {
                    let isScoped = url.startAccessingSecurityScopedResource()
                    defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
                    return try PDFPages.render(url, into: folder, maxPixels: MediaLibrary.maxPixelSize) { _, _ in }
                }.value
                var assetIDs: [UUID] = []
                for (index, page) in pages.enumerated() {
                    pdfImportStatus = "Importing page \(index + 1) of \(pages.count)…"
                    let asset = try await mediaLibrary.importImage(at: page)
                    coordinator.addMediaAsset(asset)
                    assetIDs.append(asset.id)
                }
                if let item = coordinator.addPresentation(title: title, pictures: assetIDs) {
                    browsedPresentationID = nil
                    scrollRequest = item.id
                }
            } catch {
                pdfImportProblem = error.localizedDescription
            }
        }
    }

    #if DEBUG
    /// `-PresenterDebugOpenEditor YES` opens the first playlist presentation in the editor at launch, for
    /// scripts/layout-screenshots.sh.
    private func openEditorIfAsked() {
        if UserDefaults.standard.string(forKey: ImportSongsSheet.debugFolderKey)?.isEmpty == false {
            ui.isImportingSongs = true
        }
        // `-PresenterDebugGoLive YES` puts the first slide live with a message and a prop, to check the outputs.
        if UserDefaults.standard.bool(forKey: "PresenterDebugGoLive"), let item = coordinator.project.playlist.items.first,
           let slide = coordinator.project.presentation(withID: item.presentationID)?.slides.first {
            coordinator.takeLive(slideID: slide.id, inItem: item.id)
            if let message = coordinator.project.messages.first { coordinator.showMessage(message.id) }
            if let prop = coordinator.project.props.slides.first { coordinator.toggleProp(prop.id) }
        }
        guard UserDefaults.standard.bool(forKey: "PresenterDebugOpenEditor"),
              let item = coordinator.project.playlist.items.first else { return }
        editSession = EditSession(itemID: item.id, presentationID: item.presentationID, initialSlideID: nil)
    }
    #endif

    /// The live show: playlist, continuous slide workspace, live panel and controls.
    private var showView: some View {
        NavigationSplitView {
            PlaylistSidebar(
                coordinator: coordinator,
                scrollRequest: $scrollRequest,
                browsedPresentationID: $browsedPresentationID,
                onNewSong: { ui.isAddingSong = true },
                onAddScripture: { ui.isAddingScripture = true },
                onShowShows: { ui.isShowingShows = true }
            )
                .navigationSplitViewColumnWidth(min: Widths.operatorSidebar.min, ideal: Widths.operatorSidebar.ideal, max: Widths.operatorSidebar.max)
        } detail: {
            // Plain SwiftUI stacks on purpose. HSplitView (AppKit-backed) ignored these minimum widths and
            // made the content wider than the window, clipping the sidebar and live panel; it also ignores
            // safe-area insets, so an inset control bar drew over the slide editor.
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    // HStack would split space evenly and overflow; size the live panel from what's available.
                    let liveWidth = min(max(proxy.size.width * 0.34, Widths.livePanelWidths.lowerBound), Widths.livePanelWidths.upperBound)
                    HStack(spacing: 0) {
                        workspace
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        LivePanel(coordinator: coordinator, outputManager: outputManager) { propID in
                            editSession = EditSession(itemID: nil, presentationID: coordinator.project.props.id, initialSlideID: propID)
                        }
                            .frame(width: liveWidth)
                    }
                }
                Divider()
                ControlBar(coordinator: coordinator)
            }
        }
        .navigationTitle(coordinator.project.playlist.title)
        .solidToolbar()
        .toolbar { operatorToolbar }
    }

    /// The show's slides, or a library presentation clicked in the sidebar (until it's deleted).
    @ViewBuilder
    private var workspace: some View {
        if let browsedPresentationID,
           browsedPresentationID != coordinator.project.props.id,
           let presentation = coordinator.project.presentation(withID: browsedPresentationID) {
            LibraryPresentationView(
                coordinator: coordinator,
                presentation: presentation,
                editSession: $editSession,
                onAddToShow: {
                    self.browsedPresentationID = nil
                    if let item = coordinator.addToPlaylist(presentation.id) { scrollRequest = item.id }
                },
                onBackToShow: { self.browsedPresentationID = nil }
            )
        } else {
            SlideWorkspace(coordinator: coordinator, scrollRequest: $scrollRequest, editSession: $editSession)
        }
    }

    /// On macOS 26+, each button sits on its own instead of sharing one glass capsule (see ADR 0001).
    @ToolbarContentBuilder
    private var operatorToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { quickEditToggle }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { mediaBinToggle }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { audioBinToggle }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { OutputMenu(outputManager: outputManager) { ui.editingLookRole = $0 } }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                quickEditToggle
                mediaBinToggle
                audioBinToggle
                OutputMenu(outputManager: outputManager) { ui.editingLookRole = $0 }
            }
        }
    }

    private var quickEditToggle: some View {
        Toggle(isOn: $isQuickEditVisible) {
            Label("Quick Edit", systemImage: "slider.horizontal.3")
        }
        .toggleStyle(.button)
        .help("Show or hide Quick Edit for the cued slide (⌥⌘E)")
        .accessibilityLabel("Quick Edit")
    }

    private var mediaBinToggle: some View {
        Toggle(isOn: $isMediaBinVisible) {
            Label("Media", systemImage: "photo.on.rectangle.angled")
        }
        .toggleStyle(.button)
        .help("Show or hide the media bin (⌥⌘I)")
        .accessibilityLabel("Media Bin")
    }

    private var audioBinToggle: some View {
        Toggle(isOn: $isAudioBinVisible) {
            Label("Audio", systemImage: "music.note.list")
        }
        .toggleStyle(.button)
        .help("Show or hide the audio bin (⌥⌘U)")
        .accessibilityLabel("Audio Bin")
    }
}
