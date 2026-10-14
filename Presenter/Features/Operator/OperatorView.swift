import SwiftUI
import PresenterCore

/// The operator's main window: playlist, slides, live state and controls.
struct OperatorView: View {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 300
    static let workspaceMinWidth: CGFloat = 480
    static let livePanelMinWidth: CGFloat = 300
    static let livePanelMaxWidth: CGFloat = 440
    /// The window can't shrink below this. Even with the sidebar at its widest, the workspace and
    /// live panel still get their minimum widths, so nothing is clipped.
    static let minimumWindowSize = CGSize(
        width: sidebarMaxWidth + workspaceMinWidth + livePanelMinWidth + 20,
        height: 700
    )

    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let persistence: ProjectPersistence
    @Bindable var ui: OperatorUIState
    /// A sidebar click asks the workspace to scroll to that item.
    @State private var scrollRequest: UUID?
    /// Set while the slide editor is open; it then fills the window in place of the show view.
    @State private var editSession: EditSession?
    @AppStorage("quickEditVisible") private var isQuickEditVisible = false

    var body: some View {
        Group {
            if let editSession {
                PresentationEditor(coordinator: coordinator, session: editSession, onDone: { self.editSession = nil })
            } else {
                showView
            }
        }
        .background(WindowScreenReader { outputManager.operatorWindowMoved(to: $0) })
        .sheet(isPresented: $ui.isAddingSong) {
            NewSongSheet(coordinator: coordinator) { item in scrollRequest = item.id }
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

    /// The live show: playlist, continuous slide workspace, live panel and controls.
    private var showView: some View {
        NavigationSplitView {
            PlaylistSidebar(coordinator: coordinator, scrollRequest: $scrollRequest, onNewSong: { ui.isAddingSong = true })
                .navigationSplitViewColumnWidth(min: Self.sidebarMinWidth, ideal: 240, max: Self.sidebarMaxWidth)
        } detail: {
            // Plain SwiftUI stacks on purpose. HSplitView (AppKit-backed) ignored these minimum widths and
            // made the content wider than the window, clipping the sidebar and live panel; it also ignores
            // safe-area insets, so an inset control bar drew over the slide editor.
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    // HStack would split space evenly and overflow; size the live panel from what's available.
                    let liveWidth = min(max(proxy.size.width * 0.34, Self.livePanelMinWidth), Self.livePanelMaxWidth)
                    HStack(spacing: 0) {
                        SlideWorkspace(coordinator: coordinator, scrollRequest: $scrollRequest, editSession: $editSession)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        LivePanel(coordinator: coordinator)
                            .frame(width: liveWidth)
                    }
                }
                Divider()
                ControlBar(coordinator: coordinator)
            }
        }
        .navigationTitle(coordinator.project.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $isQuickEditVisible) {
                    Label("Quick Edit", systemImage: "slider.horizontal.3")
                }
                .toggleStyle(.button)
                .help("Show or hide Quick Edit for the cued slide (⌥⌘E)")
                OutputMenu(outputManager: outputManager)
            }
        }
    }
}
