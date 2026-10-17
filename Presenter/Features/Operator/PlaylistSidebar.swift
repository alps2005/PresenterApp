import SwiftUI
import PresenterCore

struct PlaylistSidebar: View {
    let coordinator: PresentationCoordinator
    /// Clicking an item asks the workspace to scroll to it.
    @Binding var scrollRequest: UUID?
    let onNewSong: () -> Void
    @State private var itemPendingRemoval: PresentationItem?
    @State private var presentationPendingDeletion: PresentationDocument?
    @State private var searchText = ""
    @AppStorage("libraryExpanded") private var isLibraryExpanded = true

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List(selection: selection) {
            Section(coordinator.project.playlist.title) {
                ForEach(playlistItems) { item in
                    row(for: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Remove from Playlist…", role: .destructive) {
                                itemPendingRemoval = item
                            }
                        }
                }
                // Reordering a filtered list would move the wrong items, so only while not searching.
                .onMove(perform: isSearching ? nil : { coordinator.moveItems(fromOffsets: $0, toOffset: $1) })
            }

            // Every presentation, including ones taken off the playlist, like ProPresenter's library.
            Section("Library", isExpanded: Binding(get: { isLibraryExpanded || isSearching }, set: { isLibraryExpanded = $0 })) {
                ForEach(libraryPresentations) { presentation in
                    libraryRow(presentation)
                }
                if libraryPresentations.isEmpty {
                    Text(isSearching ? "No matches" : "No presentations yet")
                        .foregroundStyle(.secondary)
                }
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
            }
            .buttonStyle(.borderless)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var selection: Binding<UUID?> {
        Binding(
            get: { coordinator.state.selectedItemID },
            set: { itemID in
                guard let itemID else { return }
                coordinator.selectItem(itemID)
                scrollRequest = itemID
            }
        )
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
        .onTapGesture(count: 2) { addToPlaylist(presentation) }
        .contextMenu {
            Button("Add to Playlist") { addToPlaylist(presentation) }
            Divider()
            Button("Delete Presentation…", role: .destructive) { presentationPendingDeletion = presentation }
        }
        .help(inPlaylist ? "In the playlist. Double-click to add it again." : "Not in the playlist. Double-click to add it.")
    }

    private func addToPlaylist(_ presentation: PresentationDocument) {
        if let item = coordinator.addToPlaylist(presentation.id) {
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
