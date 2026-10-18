import SwiftUI
import PresenterCore

/// What a sidebar row selects. Typed, so rows of other kinds (themes) can't pass their IDs off as playlist items.
enum SidebarSelection: Hashable {
    case item(UUID)
    case presentation(UUID)
}

struct PlaylistSidebar: View {
    let coordinator: PresentationCoordinator
    /// Clicking an item asks the workspace to scroll to it.
    @Binding var scrollRequest: UUID?
    /// The library presentation shown in the workspace in place of the show. Nil shows the show.
    @Binding var browsedPresentationID: UUID?
    let onNewSong: () -> Void
    let onAddScripture: () -> Void
    @State private var itemPendingRemoval: PresentationItem?
    @State private var presentationPendingDeletion: PresentationDocument?
    @State private var searchText = ""
    @State private var editingThemeID: UUID?
    @State private var themePendingDeletion: Theme?
    @State private var isRenamingShow = false
    @State private var showTitleDraft = ""
    @AppStorage("libraryExpanded") private var isLibraryExpanded = true
    @AppStorage("themesExpanded") private var isThemesExpanded = true

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(playlistItems) { item in
                    row(for: item)
                        .tag(SidebarSelection.item(item.id))
                        .contextMenu {
                            Button("Remove from Playlist…", role: .destructive) {
                                itemPendingRemoval = item
                            }
                        }
                }
                // Reordering a filtered list would move the wrong items, so only while not searching.
                .onMove(perform: isSearching ? nil : { coordinator.moveItems(fromOffsets: $0, toOffset: $1) })
            } header: {
                Text(coordinator.project.playlist.title)
                    .contextMenu {
                        Button("Rename Show…") { startRenamingShow() }
                    }
                    .help("Right-click to rename the show")
            }

            // Every presentation, including ones taken off the playlist, like ProPresenter's library.
            Section("Library", isExpanded: Binding(get: { isLibraryExpanded || isSearching }, set: { isLibraryExpanded = $0 })) {
                ForEach(libraryPresentations) { presentation in
                    libraryRow(presentation)
                        .tag(SidebarSelection.presentation(presentation.id))
                }
                if libraryPresentations.isEmpty {
                    Text(isSearching ? "No matches" : "No presentations yet")
                        .foregroundStyle(.secondary)
                }
            }

            if !isSearching {
                Section("Themes", isExpanded: $isThemesExpanded) {
                    ForEach(coordinator.project.themes) { theme in
                        themeRow(theme)
                    }
                    Button {
                        if let theme = coordinator.addTheme(named: "New Theme") { editingThemeID = theme.id }
                    } label: {
                        Label("New Theme…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        // Double-clicking a library row adds it to the playlist. The List's primary action, not a tap gesture on
        // the row: a row's tap gesture swallows single clicks on its content, so only its margin selected it.
        .contextMenu(forSelectionType: SidebarSelection.self) { _ in } primaryAction: { selection in
            if selection.count == 1, case .presentation(let id) = selection.first,
               let presentation = coordinator.project.presentation(withID: id) {
                addToPlaylist(presentation)
            }
        }
        .solidSidebar()
        .hardScrollEdges()
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search titles and words")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {
                    coordinator.addPresentation(title: "Untitled")
                } label: {
                    Label("New Presentation", systemImage: "plus")
                }
                Button { onNewSong() } label: {
                    Label("New Song…", systemImage: "music.note.list")
                }
                .help("Paste lyrics to make one slide per stanza (⌥⌘N)")
                Button { onAddScripture() } label: {
                    Label("Scripture…", systemImage: "book")
                }
                .help("Add a Bible passage by its reference or by searching its words (⌥⌘V)")
            }
            .buttonStyle(.borderless)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A long library scrolls under these buttons; without a background its rows show through them.
            .background(Palette.sidebar)
        }
        .alert("Rename Show", isPresented: $isRenamingShow) {
            TextField("Name", text: $showTitleDraft)
            Button("Rename") { coordinator.renamePlaylist(to: showTitleDraft) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this presentation?",
            isPresented: Binding(
                get: { presentationPendingDeletion != nil },
                set: { if !$0 { presentationPendingDeletion = nil } }
            ),
            presenting: presentationPendingDeletion
        ) { presentation in
            Button("Delete", role: .destructive) {
                coordinator.deletePresentation(presentation.id)
            }
        } message: { presentation in
            Text("“\(presentation.title)” is removed from the library and the playlist. You can undo this with ⌘Z. If it's live, it stays on the audience output until you take something else live.")
        }
        .sheet(isPresented: Binding(get: { editingThemeID != nil }, set: { if !$0 { editingThemeID = nil } })) {
            if let editingThemeID {
                ThemeEditorSheet(coordinator: coordinator, themeID: editingThemeID)
            }
        }
        .confirmDeletion(
            "Delete this theme?",
            message: "Presentations that use it keep their look. You can undo this with ⌘Z.",
            of: $themePendingDeletion
        ) { theme in
            coordinator.deleteTheme(theme.id)
        }
        .confirmationDialog(
            "Remove this item from the playlist?",
            isPresented: Binding(
                get: { itemPendingRemoval != nil },
                set: { if !$0 { itemPendingRemoval = nil } }
            ),
            presenting: itemPendingRemoval
        ) { item in
            Button("Remove", role: .destructive) {
                coordinator.removeItem(item.id)
            }
        } message: { _ in
            Text("What's on the audience output won't change.")
        }
    }

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let browsedPresentationID { return .presentation(browsedPresentationID) }
                return coordinator.state.selectedItemID.map { .item($0) }
            },
            set: { selection in
                switch selection {
                case .item(let itemID):
                    browsedPresentationID = nil
                    coordinator.selectItem(itemID)
                    scrollRequest = itemID
                case .presentation(let presentationID):
                    browsedPresentationID = presentationID
                case nil:
                    break
                }
            }
        )
    }

    private func startRenamingShow() {
        showTitleDraft = coordinator.project.playlist.title
        isRenamingShow = true
    }

    private var playlistItems: [PresentationItem] {
        guard isSearching else { return coordinator.project.playlist.items }
        return coordinator.project.playlist.items.filter {
            coordinator.project.presentation(withID: $0.presentationID)?.matches(searchText) ?? false
        }
    }

    private var libraryPresentations: [PresentationDocument] {
        coordinator.project.presentations
            .filter { $0.matches(searchText) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func libraryRow(_ presentation: PresentationDocument) -> some View {
        let inPlaylist = coordinator.project.playlist.items.contains { $0.presentationID == presentation.id }
        return HStack {
            Label(presentation.title.isEmpty ? "Untitled" : presentation.title, systemImage: "doc.text")
                .foregroundStyle(inPlaylist ? .primary : .secondary)
            Spacer()
            // Not by colour alone: a mark shows which presentations are already in the playlist.
            if inPlaylist {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .help("In the playlist")
                    .accessibilityLabel("In the playlist")
            }
            Button {
                addToPlaylist(presentation)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add to Playlist")
            .accessibilityLabel("Add \(presentation.title.isEmpty ? "Untitled" : presentation.title) to Playlist")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Add to Playlist") { addToPlaylist(presentation) }
            Divider()
            Button("Delete Presentation…", role: .destructive) { presentationPendingDeletion = presentation }
        }
        .help(inPlaylist ? "In the playlist. Double-click to add it again." : "Not in the playlist. Double-click to add it.")
    }

    private func themeRow(_ theme: Theme) -> some View {
        let isDefault = coordinator.project.defaultThemeID == theme.id
        return HStack {
            Label(theme.name.isEmpty ? "Untitled Theme" : theme.name, systemImage: "paintpalette")
            Spacer()
            // An icon and a word, not colour alone.
            if isDefault {
                Label("Default", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("New songs and presentations use this theme")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingThemeID = theme.id }
        .contextMenu {
            Button("Edit Theme…") { editingThemeID = theme.id }
            Button("Duplicate") {
                if let copy = coordinator.addTheme(named: "\(theme.name) Copy", basedOn: theme.id) { editingThemeID = copy.id }
            }
            if isDefault {
                Button("Don't Use for New Songs") { coordinator.setDefaultTheme(nil) }
            } else {
                Button("Use for New Songs") { coordinator.setDefaultTheme(theme.id) }
            }
            Divider()
            Button("Delete Theme…", role: .destructive) { themePendingDeletion = theme }
        }
        .help("Double-click to edit. Choose a presentation's theme in the editor's Document settings.")
    }

    private func addToPlaylist(_ presentation: PresentationDocument) {
        if let item = coordinator.addToPlaylist(presentation.id) {
            browsedPresentationID = nil
            scrollRequest = item.id
        }
    }

    @ViewBuilder
    private func row(for item: PresentationItem) -> some View {
        if let presentation = coordinator.project.presentation(withID: item.presentationID) {
            HStack {
                Label(presentation.title.isEmpty ? "Untitled" : presentation.title, systemImage: "doc.text")
                Spacer()
                if coordinator.state.live?.position.itemID == item.id {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Palette.live)
                        .help("Live")
                        .accessibilityLabel("Live")
                }
                Text("\(presentation.slides.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            WarningLabel("Missing presentation")
        }
    }
}
