import SwiftUI
import PresenterCore

/// The project's shows, most recently opened first, with Rename, Duplicate and Delete in the right-click menu.
/// Double-click or Return opens one. Shared by the welcome window and the Shows sheet.
struct ShowList: View {
    let coordinator: PresentationCoordinator
    @Binding var selectedID: UUID?
    /// Set to ask for a new show's name; the show is made and opened when it's confirmed.
    @Binding var isNamingNewShow: Bool
    /// Called after a show is opened or made.
    let onOpened: () -> Void

    @State private var renamingID: UUID?
    @State private var nameDraft = ""
    @State private var showPendingDeletion: PlaylistDocument?

    var body: some View {
        List(selection: $selectedID) {
            ForEach(Self.sortedShows(in: coordinator.project)) { show in
                row(show)
                    .tag(show.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let show = coordinator.project.playlist(withID: id) {
                Button("Open") { open(id) }
                Button("Rename…") {
                    nameDraft = show.title
                    renamingID = id
                }
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
        .onChange(of: isNamingNewShow) { _, isNaming in
            if isNaming { nameDraft = "" }
        }
        .alert("New Show", isPresented: $isNamingNewShow) {
            TextField("Name", text: $nameDraft)
            Button("Create") {
                coordinator.addPlaylist(title: nameDraft)
                onOpened()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Show", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Name", text: $nameDraft)
            Button("Rename") {
                if let renamingID { coordinator.renamePlaylist(renamingID, to: nameDraft) }
            }
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

    /// The open show, then the most recently opened; shows never opened keep the order they were made in, last.
    static func sortedShows(in project: ProjectDocument) -> [PlaylistDocument] {
        let openID = project.activePlaylistID
        return project.playlists.enumerated().sorted { lhs, rhs in
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
        return HStack(spacing: Spacing.md) {
            Image(systemName: "rectangle.stack")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
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
    }
}
