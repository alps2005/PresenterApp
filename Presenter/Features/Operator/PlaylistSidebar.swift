import SwiftUI
import PresenterCore

struct PlaylistSidebar: View {
    let coordinator: PresentationCoordinator
    /// Clicking an item asks the workspace to scroll to it.
    @Binding var scrollRequest: UUID?
    @State private var itemPendingRemoval: PresentationItem?

    var body: some View {
        List(selection: selection) {
            Section(coordinator.project.playlist.title) {
                ForEach(coordinator.project.playlist.items) { item in
                    row(for: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Remove from Playlist…", role: .destructive) {
                                itemPendingRemoval = item
                            }
                        }
                }
                .onMove { coordinator.moveItems(fromOffsets: $0, toOffset: $1) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                coordinator.addPresentation(title: "Untitled")
            } label: {
                Label("New Presentation", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func row(for item: PresentationItem) -> some View {
        if let presentation = coordinator.project.presentation(withID: item.presentationID) {
            HStack {
                Label(presentation.title.isEmpty ? "Untitled" : presentation.title, systemImage: "doc.text")
                Spacer()
                if coordinator.state.live?.position.itemID == item.id {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.red)
                        .help("Live")
                }
                Text("\(presentation.slides.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Missing presentation", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
