import SwiftUI
import PresenterCore

/// Show Controls › Messages: messages shown over the slides, with blanks filled in when they're shown.
struct MessagesTab: View {
    let coordinator: PresentationCoordinator
    @State private var showing: MessageDefinition?
    @State private var editing: MessageDraft?
    @State private var pendingDeletion: MessageDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(coordinator.project.messages) { message in
                row(message)
            }
            Button {
                editing = MessageDraft(message: nil)
            } label: {
                Label("New Message", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .popover(item: Binding(get: { editing?.message == nil ? editing : nil }, set: { editing = $0 })) { draft in
                MessageEditor(coordinator: coordinator, draft: draft) { editing = nil }
            }
            Text("Write {Name} for a blank you fill in when showing the message, or {timer:Sermon} for a live timer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmDeletion("Delete “\(pendingDeletion?.name ?? "")”?",
                         message: "If it's on screen, it stays until you clear messages. You can undo this.",
                         of: $pendingDeletion) { message in
            coordinator.deleteMessage(message.id)
        }
    }

    private func row(_ message: MessageDefinition) -> some View {
        let isShowing = coordinator.state.activeMessage?.messageID == message.id
        return RowCard(isHighlighted: isShowing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(message.name).lineLimit(1)
                Text(message.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isShowing {
                StateBadge(.live)
                Button("Hide") { coordinator.clearMessages() }
            } else {
                // The ellipsis only when there are blanks to fill in first.
                Button(message.fields.isEmpty ? "Show" : "Show…") {
                    if message.fields.isEmpty {
                        coordinator.showMessage(message.id)
                    } else {
                        showing = message
                    }
                }
                .popover(item: Binding(get: { showing?.id == message.id ? showing : nil }, set: { showing = $0 })) { message in
                    MessageFieldsForm(coordinator: coordinator, message: message) { showing = nil }
                }
            }
            RowMenuButton(subject: message.name) {
                Button("Edit…") { editing = MessageDraft(message: message) }
                Divider()
                Button("Delete…", role: .destructive) { pendingDeletion = message }
            }
            .popover(item: Binding(get: { editing?.message?.id == message.id ? editing : nil }, set: { editing = $0 })) { draft in
                MessageEditor(coordinator: coordinator, draft: draft) { editing = nil }
            }
        }
    }
}

/// Fill in a message's blanks, then show it.
private struct MessageFieldsForm: View {
    let coordinator: PresentationCoordinator
    let message: MessageDefinition
    let onDone: () -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        PopoverForm(message.name, primary: "Show", onCancel: onDone, onSubmit: show) {
            ForEach(message.fields, id: \.self) { field in
                TextField(field, text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            Text(coordinator.messageText(message, values: values, at: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func show() {
        coordinator.showMessage(message.id, values: values)
        onDone()
    }
}

private struct MessageDraft: Identifiable {
    let message: MessageDefinition?
    var id: String { message?.id.uuidString ?? "new" }
}

private struct MessageEditor: View {
    let coordinator: PresentationCoordinator
    let draft: MessageDraft
    let onDone: () -> Void
    @State private var message = MessageDefinition(name: "", text: "")

    var body: some View {
        PopoverForm(draft.message == nil ? "New Message" : "Edit Message", primary: draft.message == nil ? "Add" : "Save",
                    width: 320, canSubmit: isValid, onCancel: onDone, onSubmit: save) {
            TextField("Name", text: $message.name).textFieldStyle(.roundedBorder)
            TextField("Text, e.g. Parent of child {Number}…", text: $message.text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            Picker("Position", selection: $message.position) {
                Text("Bottom").tag(MessageDefinition.Position.bottom)
                Text("Top").tag(MessageDefinition.Position.top)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Size")
                Slider(value: $message.fontSize, in: 32...140)
            }
            HStack {
                ColorPicker("Text", selection: Binding(get: { message.textColor.color }, set: { message.textColor = RGBAColor($0) }))
                ColorPicker("Bar", selection: Binding(get: { message.barColor.color }, set: { message.barColor = RGBAColor($0) }),
                            supportsOpacity: true)
            }
        }
        .onAppear { if let existing = draft.message { message = existing } }
    }

    private var isValid: Bool { !message.text.trimmingCharacters(in: .whitespaces).isEmpty }

    private func save() {
        if draft.message != nil {
            coordinator.updateMessage(message)
        } else {
            coordinator.addMessage(message)
        }
        onDone()
    }
}

/// Show Controls › Props: logos and other graphics that stay over the slides until hidden.
struct PropsTab: View {
    let coordinator: PresentationCoordinator
    /// Opens the slide editor on the props, starting with this one.
    let onEdit: (UUID?) -> Void
    @State private var renaming: SlideDocument?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            let props = coordinator.project.props
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(props.slides) { prop in
                    tile(prop, props: props)
                }
            }
            HStack {
                Button {
                    let prop = coordinator.addProp(name: "Prop \(props.slides.count + 1)")
                    onEdit(prop.id)
                } label: {
                    Label("New Prop", systemImage: "plus")
                }
                Spacer()
                Button("Edit Props…") { onEdit(nil) }
                    .disabled(props.slides.isEmpty)
            }
            .buttonStyle(.borderless)
            Text("Click a prop to show or hide it over the slides. Several can be on screen at once.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tile(_ prop: SlideDocument, props: PresentationDocument) -> some View {
        let isShowing = coordinator.state.activeProps.contains(prop.id)
        let isEdited = coordinator.propHasPendingEdits(prop.id)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            SlideRenderView(scene: .slide(props.rendered(prop)))
                .aspectRatio(16 / 9, contentMode: .fit)
                .tileFrame(TileState(isLive: isShowing), cornerRadius: Radius.badge)
            HStack(spacing: Spacing.xs) {
                Text(prop.label ?? "Prop").font(.caption).lineLimit(1)
                Spacer()
                if isEdited { StateBadge(.edited) }
                if isShowing { StateBadge(.live) }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { coordinator.toggleProp(prop.id) }
        .help(isEdited ? "Edited since it was shown. Hide and show it again to put the changes on screen."
              : isShowing ? "Click to hide" : "Click to show over the slides")
        .contextMenu {
            Button(isShowing ? "Hide" : "Show") { coordinator.toggleProp(prop.id) }
            Button("Edit…") { onEdit(prop.id) }
            Button("Rename…") {
                name = prop.label ?? ""
                renaming = prop
            }
            Divider()
            Button("Delete", role: .destructive) { coordinator.deleteProp(prop.id) }
        }
        .popover(item: Binding(get: { renaming?.id == prop.id ? renaming : nil }, set: { renaming = $0 })) { prop in
            PopoverForm("Rename Prop", primary: "Rename", width: 240, onCancel: { renaming = nil }) {
                coordinator.renameProp(prop.id, to: name)
                renaming = nil
            } fields: {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            }
        }
    }
}
