import AppKit
import PresenterCore
import SwiftUI

/// The window Presenter opens with, like Xcode's "Welcome to Xcode": pick a show to present, make one, or open a
/// project. Opening a show brings up the operator window and closes this one. Window › Welcome to Presenter (⇧⌘1)
/// opens it again later; the in-window Shows sheet (⇧⌘O) stays for quick switching mid-service.
struct WelcomeView: View {
    static let windowID = "welcome"
    /// The "Show this window when Presenter opens" checkbox. (The name is from when this was the Shows sheet.)
    static let showAtLaunchKey = "showShowsAtLaunch"
    static let size = CGSize(width: 480, height: 620)

    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let persistence: ProjectPersistence
    let ui: OperatorUIState
    let updater: UpdaterController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Self.showAtLaunchKey) private var showsAtLaunch = true
    @State private var selectedID: UUID?
    @State private var isNamingNewShow = false
    /// Set when this window closes because the operator window is taking over, so closing it doesn't quit.
    @State private var isHandingOver = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            header
            actions
            ShowList(coordinator: coordinator, selectedID: $selectedID, isNamingNewShow: $isNamingNewShow) {
                openOperatorWindow()
            }
            .scrollContentBackground(.hidden)
            .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline.opacity(0.5)))
            if let version = updater.availableVersion {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Presenter \(version) is available", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Toggle("Show this window when Presenter opens", isOn: $showsAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(.ui(.callout))
                Spacer()
                Button("Open") {
                    if let selectedID, coordinator.openPlaylist(selectedID).isApplied { openOperatorWindow() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedID == nil)
                .help("Open the selected show (or double-click it)")
            }
        }
        .padding(.horizontal, Spacing.xl + Spacing.sm)
        .padding(.top, Spacing.xl * 2)
        .padding(.bottom, Spacing.xl)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.sidebar)
        .background(WelcomeWindowStyler())
        .operatorLook()
        .onAppear {
            selectedID = coordinator.project.activePlaylistID
            // With the checkbox off, Presenter starts in the operator window. Only at launch: reopened later
            // with ⇧⌘1, the window stays.
            if !showsAtLaunch && !ui.hasShownOperatorWindow { openOperatorWindow() }
        }
        .onDisappear {
            // ✕ (or ⌘W) at launch quits, as the user asked; once the operator window is open it only closes. Never
            // quit mid-service (reopened from the Dock with the operator window closed): go back to the operator.
            if !isHandingOver && !ui.isOperatorWindowOpen {
                if coordinator.state.isPresenting(outputsShowing: outputManager.isAnyOutputOn) {
                    openWindow(id: "operator")
                } else {
                    NSApp.terminate(nil)
                }
            }
            isHandingOver = false
        }
        .onExitCommand {
            // A stray Esc at launch mustn't quit.
            if ui.isOperatorWindowOpen { dismissWindow(id: Self.windowID) }
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Presenter")
                .font(.system(size: 30, weight: .bold))
            Text(Self.versionText)
                .font(.ui(.callout))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                openOperatorWindow()
                persistence.openProject()
            } label: {
                Label("Open Project…", systemImage: "folder")
                    .labelStyle(WelcomeActionLabelStyle())
            }
            .help("Replace this project with one exported from Presenter")
            Button {
                openOperatorWindow()
                ui.isImportingSongs = true
            } label: {
                Label("Import Songs…", systemImage: "music.note.list")
                    .labelStyle(WelcomeActionLabelStyle())
            }
            .help("Add OpenLyrics, ChordPro or SongSelect files to the open show")
            Menu {
                Button("New Empty Show…") { isNamingNewShow = true }
                if let selectedID, let show = coordinator.project.playlist(withID: selectedID) {
                    Button("Duplicate “\(show.title)”") {
                        if let copy = coordinator.duplicatePlaylist(selectedID) { self.selectedID = copy.id }
                    }
                }
            } label: {
                // The chevron stands in for the menu indicator, which the custom button style doesn't draw.
                Label {
                    HStack(spacing: Spacing.xs) {
                        Text("New Show")
                        Image(systemName: "chevron.down")
                            .font(.ui(.caption2).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "plus")
                }
                .labelStyle(WelcomeActionLabelStyle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .help("Make a new show, or a copy of the selected one")
        }
        .buttonStyle(WelcomeActionButtonStyle())
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Version 1.5.0", from the bundle (CI sets it from the tag). The build number stays out of sight: only the
    /// updater needs it, and About Presenter still shows it.
    static var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return String(localized: "Version \(version)")
    }

    private func openOperatorWindow() {
        isHandingOver = true
        openWindow(id: "operator")
        dismissWindow(id: Self.windowID)
    }
}

/// Makes the welcome window look like a panel rather than a document window: no minimize or zoom buttons, and it
/// moves by dragging anywhere on its background.
private struct WelcomeWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The welcome window's three actions as one shape. A system bordered button wouldn't do: macOS draws the New Show
/// menu at a fixed height with the icon beside the words, so it came out thinner than the other two.
private struct WelcomeActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.sm)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.2 : 0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
    }
}

/// The welcome window's three actions: the icon above the words, so longer translations ("Importar canciones…")
/// fit the narrow window without shrinking.
private struct WelcomeActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: Spacing.xxs) {
            configuration.icon
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxs)
    }
}
