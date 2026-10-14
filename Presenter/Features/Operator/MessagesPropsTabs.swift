import SwiftUI
import PresenterCore

/// Show Controls › Messages: messages shown over the slides, with blanks filled in when they're shown.
struct MessagesTab: View {
    let coordinator: PresentationCoordinator
    @State private var showing: MessageDefinition?
    @State private var editing: MessageDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }

    private func row(_ message: MessageDefinition) -> some View {
        let isShowing = coordinator.state.activeMessage?.messageID == message.id
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(message.name).lineLimit(1)
                Text(message.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isShowing {
                Button("Hide") { coordinator.clearMessages() }
                    .tint(.red)
            } else {
                Button("Show…") {
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
            Menu {
                Button("Edit…") { editing = MessageDraft(message: message) }
                Divider()
                Button("Delete", role: .destructive) { coordinator.deleteMessage(message.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(item: Binding(get: { editing?.message?.id == message.id ? editing : nil }, set: { editing = $0 })) { draft in
                MessageEditor(coordinator: coordinator, draft: draft) { editing = nil }
            }
        }
        .padding(8)
        .background(isShowing ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Fill in a message's blanks, then show it.
private struct MessageFieldsForm: View {
    let coordinator: PresentationCoordinator
    let message: MessageDefinition
    let onDone: () -> Void
    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.name).font(.headline)
            ForEach(message.fields, id: \.self) { field in
                TextField(field, text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            Text(coordinator.messageText(message, values: values, at: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                Button("Show") {
                    coordinator.showMessage(message.id, values: values)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.message == nil ? "New Message" : "Edit Message").font(.headline)
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
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                Button(draft.message == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(message.text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { if let existing = draft.message { message = existing } }
    }

    private func save() {
        if draft.message != nil {
            coordinator.updateMessage(message)
        } else {
            var added = coordinator.addMessage(name: message.name, text: message.text)
            added.position = message.position
            added.fontSize = message.fontSize
            added.textColor = message.textColor
            added.barColor = message.barColor
            coordinator.updateMessage(added)
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
        VStack(alignment: .leading, spacing: 6) {
            let props = coordinator.project.props
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
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
        return VStack(alignment: .leading, spacing: 3) {
            SlideRenderView(scene: .slide(props.rendered(prop)))
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isShowing ? Color.red : Color.secondary.opacity(0.4), lineWidth: isShowing ? 2 : 1)
                }
            HStack(spacing: 4) {
                Text(prop.label ?? "Prop").font(.caption).lineLimit(1)
                Spacer()
                if isShowing { StateBadge(text: "ON", color: .red) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { coordinator.toggleProp(prop.id) }
        .help(isShowing ? "Click to hide" : "Click to show over the slides")
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
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Rename") {
                        coordinator.renameProp(prop.id, to: name)
                        renaming = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 240)
        }
    }
}
