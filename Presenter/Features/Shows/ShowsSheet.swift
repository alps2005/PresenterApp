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
    @State private var naming: ShowNaming?
    @State private var nameDraft = ""
    @State private var showPendingDeletion: PlaylistDocument?

    var body: some View {
        HStack(spacing: 0) {
            sidePanel
                .frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                showList
                Divider()
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Open") {
                        if let selectedID { open(selectedID) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 660, height: 420)
        .onAppear { selectedID = coordinator.project.activePlaylistID }
        .alert(naming?.title ?? "", isPresented: Binding(
            get: { naming != nil },
            set: { if !$0 { naming = nil } }
        ), presenting: naming) { naming in
            TextField("Name", text: $nameDraft)
            Button(naming.confirmTitle) { finishNaming(naming) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmDeletion(
            "Delete this show?",
            message: deletionMessage,
            of: $showPendingDeletion
        ) { show in
            coordinator.deletePlaylist(show.id)
            if selectedID == show.id { selectedID = coordinator.project.activePlaylistID }
        }
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
                startNaming(.new)
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

    private var showList: some View {
        List(selection: $selectedID) {
            ForEach(sortedShows) { show in
                row(show)
                    .tag(show.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let show = coordinator.project.playlist(withID: id) {
                Button("Open") { open(id) }
                Button("Rename…") { startNaming(.rename(id), name: show.title) }
                Button("Duplicate") {
                    if let copy = coordinator.duplicatePlaylist(id) { selectedID = copy.id }
                }
                Divider()
                Button("Delete…", role: .destructive) { showPendingDeletion = show }
                    .disabled(coordinator.project.playlists.count < 2)
            }
        } primaryAction: { ids in
            if let id = ids.first { open(id) }
        }
    }

    /// The open show, then the most recently opened; shows never opened keep the order they were made in, last.
    private var sortedShows: [PlaylistDocument] {
        let shows = coordinator.project.playlists
        let openID = coordinator.project.activePlaylistID
        return shows.enumerated().sorted { lhs, rhs in
            if lhs.element.id == openID || rhs.element.id == openID { return lhs.element.id == openID }
            return switch (lhs.element.lastOpenedAt, rhs.element.lastOpenedAt) {
            case let (l?, r?): l > r
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private func row(_ show: PlaylistDocument) -> some View {
        let isOpen = show.id == coordinator.project.activePlaylistID
        return HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(show.title)
                    .font(.headline)
                Text(detail(for: show))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // A word and an icon, not colour alone.
            if isOpen {
                Label("Open", systemImage: "checkmark.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .help(isOpen ? "The open show" : "Double-click to open")
    }

    private func detail(for show: PlaylistDocument) -> String {
        let count = show.items.count == 1 ? "1 item" : "\(show.items.count) items"
        guard let opened = show.lastOpenedAt else { return count }
        return "\(count) · Opened \(opened.formatted(.relative(presentation: .named)))"
    }

    private var deletionMessage: String {
        guard let show = showPendingDeletion else { return "" }
        let library = "Its presentations stay in the library."
        guard show.id == coordinator.project.activePlaylistID else {
            return "\(library) You can undo this with ⌘Z."
        }
        return "\(library) It's the open show, so the show you opened before it opens instead. This can't be undone. What's on the audience output won't change."
    }

    private func open(_ id: UUID) {
        guard coordinator.openPlaylist(id).isApplied else { return }
        onOpened()
        dismiss()
    }

    private func startNaming(_ naming: ShowNaming, name: String = "") {
        nameDraft = name
        self.naming = naming
    }

    private func finishNaming(_ naming: ShowNaming) {
        switch naming {
        case .new:
            coordinator.addPlaylist(title: nameDraft)
            onOpened()
            dismiss()
        case .rename(let id):
            coordinator.renamePlaylist(id, to: nameDraft)
        }
    }
}

/// Naming a show: a new one, or renaming one.
private enum ShowNaming {
    case new
    case rename(UUID)

    var title: String {
        switch self {
        case .new: "New Show"
        case .rename: "Rename Show"
        }
    }

    var confirmTitle: String {
        switch self {
        case .new: "Create"
        case .rename: "Rename"
        }
    }
}
