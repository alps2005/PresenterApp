import SwiftUI
import PresenterCore

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
    /// A sidebar click asks the workspace to scroll to that item.
    @State private var scrollRequest: UUID?
    /// A library presentation clicked in the sidebar, shown in place of the show's slides.
    @State private var browsedPresentationID: UUID?
    /// Set while the slide editor is open; it then fills the window in place of the show view.
    @State private var editSession: EditSession?
    @AppStorage("quickEditVisible") private var isQuickEditVisible = false
    @AppStorage("mediaBinVisible") private var isMediaBinVisible = false
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
        .sheet(isPresented: $ui.isAddingSong) {
            NewSongSheet(coordinator: coordinator) { item in scrollRequest = item.id }
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

    #if DEBUG
    /// `-PresenterDebugOpenEditor YES` opens the first playlist presentation in the editor at launch, for
    /// scripts/layout-screenshots.sh.
    private func openEditorIfAsked() {
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
                onNewSong: { ui.isAddingSong = true }
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
            ToolbarItem(placement: .primaryAction) { OutputMenu(outputManager: outputManager) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                quickEditToggle
                mediaBinToggle
                OutputMenu(outputManager: outputManager)
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
}
