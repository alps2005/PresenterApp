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

    var body: some View {
        NavigationSplitView {
            PlaylistSidebar(coordinator: coordinator)
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
                        SlideWorkspace(coordinator: coordinator)
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
            ToolbarItem(placement: .primaryAction) {
                OutputMenu(outputManager: outputManager)
            }
        }
        .background(WindowScreenReader { outputManager.operatorWindowMoved(to: $0) })
    }
}
