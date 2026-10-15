import SwiftUI
import PresenterCore

/// Builds the order a presentation's groups play in: tap a group to add it (repeats allowed),
/// tap it in the order to remove it.
struct ArrangementSheet: View {
    let coordinator: PresentationCoordinator
    let draft: ArrangementDraft

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var groups: [String] = []
    @State private var isConfirmingDelete = false

    private var presentation: PresentationDocument? {
        coordinator.project.presentation(withID: draft.presentationID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.arrangement == nil ? "New Arrangement" : "Edit Arrangement").font(.title2.bold())

            TextField("Name, e.g. Sunday Morning", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Groups").font(.subheadline.bold())
                Text("Click a group to add it to the end. A group can play more than once.")
                    .font(.caption).foregroundStyle(.secondary)
                FlowRow(items: presentation?.groupNames ?? []) { group in
                    Button {
                        groups.append(group)
                    } label: {
                        GroupLabelTag(label: group)
                    }
                    .buttonStyle(.plain)
                    .help("Add \(group)")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Play order").font(.subheadline.bold())
                if groups.isEmpty {
                    Text("Empty: the presentation plays in slide order.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    FlowRow(items: Array(groups.enumerated()).map { IndexedGroup(index: $0.offset, name: $0.element) }) { entry in
                        Button {
                            groups.remove(at: entry.index)
                        } label: {
                            HStack(spacing: 3) {
                                GroupLabelTag(label: entry.name)
                                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Remove this \(entry.name)")
                    }
                    Button("Clear") { groups.removeAll() }
                        .controlSize(.small)
                }
            }

            HStack {
                if draft.arrangement != nil {
                    Button("Delete…", role: .destructive) { isConfirmingDelete = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.arrangement == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            name = draft.arrangement?.name ?? ""
            groups = draft.arrangement?.groups ?? []
        }
        .confirmationDialog("Delete this arrangement?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                if let arrangement = draft.arrangement {
                    coordinator.deleteArrangement(arrangement.id, inPresentation: draft.presentationID)
                }
                dismiss()
            }
        } message: {
            Text("The slides stay; only this play order is removed.")
        }
    }

    private func save() {
        if var arrangement = draft.arrangement {
            arrangement.name = name.isEmpty ? arrangement.name : name
            arrangement.groups = groups
            coordinator.updateArrangement(arrangement, inPresentation: draft.presentationID)
        } else {
            coordinator.addArrangement(name: name, groups: groups, toPresentation: draft.presentationID)
        }
        dismiss()
    }

    private struct IndexedGroup: Hashable {
        let index: Int
        let name: String
    }
}

/// Lays out items left to right, wrapping onto new lines.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in content(item) }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
