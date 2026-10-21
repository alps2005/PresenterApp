import SwiftUI
import PresenterCore

/// Lists the project's shows, most recently opened first, to open one or make a new one. Shown at launch (unless
/// turned off) and from File › Shows…, like Xcode's welcome window.
struct ShowsSheet: View {
    static let showAtLaunchKey = "showShowsAtLaunch"

    let coordinator: PresentationCoordinator
    /// Called after a show is opened, so the operator window can leave a library presentation it was showing.
    let onOpened: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Self.showAtLaunchKey) private var showsAtLaunch = true
    @State private var selectedID: UUID?
    @State private var isNamingNewShow = false

    var body: some View {
        HStack(spacing: 0) {
            sidePanel
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                ShowList(coordinator: coordinator, selectedID: $selectedID, isNamingNewShow: $isNamingNewShow) {
                    onOpened()
                    dismiss()
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Open") {
                        if let selectedID, coordinator.openPlaylist(selectedID).isApplied {
                            onOpened()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 660, height: 420)
        .onAppear { selectedID = coordinator.project.activePlaylistID }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Shows").font(.title2.bold())
            Text("Each show is a playlist. All of them use the same library, so a change to a song shows in every show that has it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isNamingNewShow = true
            } label: {
                Label("New Show…", systemImage: "plus")
            }
            Spacer()
            Toggle("Show this window when Presenter opens", isOn: $showsAtLaunch)
                .toggleStyle(.checkbox)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.xl)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
