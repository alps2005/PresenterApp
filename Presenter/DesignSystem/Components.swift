import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Shared pieces of the operator UI, so the same thing looks and reads the same everywhere.

// MARK: - State badges

/// A state of something on (or headed for) the audience output.
enum ShowState {
    case live
    case cued
    case blackout
    /// Only the background layer is on screen: no words.
    case backgroundOnly
    /// The slide was cleared and can be restored.
    case cleared
    case nothingLive
    /// Changed since it went on screen.
    case edited

    var title: String {
        switch self {
        case .live: "LIVE"
        case .cued: "CUED"
        case .blackout: "BLACKOUT"
        case .backgroundOnly: "BACKGROUND ONLY"
        case .cleared: "CLEARED"
        case .nothingLive: "NOTHING LIVE"
        case .edited: "EDITED"
        }
    }

    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .cued: "arrow.right.circle.fill"
        case .blackout: "moon.fill"
        case .backgroundOnly: "photo"
        case .cleared: "eye.slash"
        case .nothingLive: "circle.dashed"
        case .edited: "pencil"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .live: "Live"
        case .cued: "Cued"
        case .blackout: "Blackout"
        case .backgroundOnly: "Background only"
        case .cleared: "Cleared"
        case .nothingLive: "Nothing live"
        case .edited: "Edited"
        }
    }
}

/// An icon and a word, so a state never depends on colour alone. Each state has its own shape as well as
/// colour: filled for live, cued, edited and cleared, outlined for background only and nothing live,
/// and black with a red outline for blackout.
struct StateBadge: View {
    let state: ShowState

    init(_ state: ShowState) {
        self.state = state
    }

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .labelStyle(.titleAndIcon)
            .font(Typography.badge)
            .lineLimit(1)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.badge))
            .overlay {
                if let outline {
                    RoundedRectangle(cornerRadius: Radius.badge).strokeBorder(outline, lineWidth: 1.5)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilityLabel)
    }

    private var fill: Color {
        switch self.state {
        case .live: Palette.live
        case .cued: Palette.cued
        case .edited: Palette.edited
        case .blackout: Palette.blackout
        case .cleared: Palette.idle
        case .backgroundOnly, .nothingLive: .clear
        }
    }

    private var foreground: Color {
        switch self.state {
        case .backgroundOnly: Palette.live
        case .nothingLive: .secondary
        default: .white
        }
    }

    private var outline: Color? {
        switch self.state {
        case .blackout, .backgroundOnly: Palette.live
        case .nothingLive: Palette.hairline
        default: nil
        }
    }
}

// MARK: - Tile frames

/// Whether a thumbnail or preview is on the output, cued, or neither.
enum TileState {
    case idle
    case cued
    case live

    init(isLive: Bool, isCued: Bool = false) {
        self = isLive ? .live : isCued ? .cued : .idle
    }
}

extension View {
    /// Rounds a slide or media tile and outlines it by state: red when live, blue when cued, a hairline otherwise.
    func tileFrame(_ state: TileState, cornerRadius: CGFloat = Radius.tile) -> some View {
        let color: Color = switch state {
        case .live: Palette.live
        case .cued: Palette.cued
        case .idle: Palette.hairline
        }
        return clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color, lineWidth: state == .idle ? 1 : 3)
            }
    }
}

// MARK: - Labels, rows and headers

/// Something that needs the operator's attention, such as missing media. Always amber, always with an icon.
struct WarningLabel: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"
    var font = Font.caption

    init(_ text: String, systemImage: String = "exclamationmark.triangle.fill", font: Font = .caption) {
        self.text = text
        self.systemImage = systemImage
        self.font = font
    }

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(font)
            .foregroundStyle(Palette.warning)
    }
}

/// A list row on a raised card, as in Show Controls' timers and messages.
struct RowCard<Content: View>: View {
    var isHighlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: Spacing.sm) { content }
            .padding(Spacing.md)
            .background(Palette.panelRaised, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.live, lineWidth: 2)
                }
            }
    }
}

/// The ⋯ menu at the end of a row, labelled for VoiceOver.
struct RowMenuButton<Items: View>: View {
    /// What the row is, for VoiceOver and the tooltip: "More for Sermon".
    let subject: String
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More for \(subject)")
        .accessibilityLabel("More for \(subject)")
    }
}

/// A section title with optional trailing controls, as at the top of the live panel and the media bin.
struct PanelHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A small form in a popover: a title, its fields, and Cancel plus a primary button. Return in any field
/// submits it (a popover's text fields don't reach its default button on their own).
struct PopoverForm<Fields: View>: View {
    let title: String?
    let primaryTitle: String
    var width: CGFloat = 300
    var canSubmit = true
    let onCancel: (() -> Void)?
    let onSubmit: () -> Void
    @ViewBuilder let fields: Fields

    init(
        _ title: String?,
        primary primaryTitle: String,
        width: CGFloat = 300,
        canSubmit: Bool = true,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping () -> Void,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self.primaryTitle = primaryTitle
        self.width = width
        self.canSubmit = canSubmit
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.fields = fields()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title { Text(title).font(.headline) }
            fields
                .onSubmit { if canSubmit { onSubmit() } }
            HStack {
                Spacer()
                if let onCancel {
                    Button("Cancel", role: .cancel) { onCancel() }
                }
                Button(primaryTitle) { onSubmit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(Spacing.lg)
        .frame(width: width)
    }
}

// MARK: - Shared panels and confirmations

enum MediaPanel {
    /// Asks the operator for media files of these types. Returns nothing if they cancel. NSOpenPanel rather than
    /// `.fileImporter`: callers can live in a popover that closes when the panel takes focus, which would drop a
    /// SwiftUI importer's callback.
    static func choose(_ types: [UTType], multiple: Bool = false, message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = message
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }
}

extension View {
    /// Asks before deleting `item` once it's set, and clears it when the dialog closes.
    func confirmDeletion<Item>(
        _ title: String, message: String, of item: Binding<Item?>, onDelete: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
            presenting: item.wrappedValue
        ) { pending in
            Button("Delete", role: .destructive) { onDelete(pending) }
        } message: { _ in
            Text(message)
        }
    }

    /// Asks before deleting a slide, explaining that a live slide stays on the output.
    func confirmSlideDeletion<Item>(of item: Binding<Item?>, onDelete: @escaping (Item) -> Void) -> some View {
        confirmDeletion(
            "Delete this slide?",
            message: "If this slide is live, it stays on the audience output until you take another slide live.",
            of: item,
            onDelete: onDelete
        )
    }
}
