import PresenterCore
import SwiftUI

extension ShowAction {
    /// What the action does, in words, with an icon. `isMissing` when what it points at is gone, so it does nothing.
    func summary(in project: ProjectDocument) -> (text: String, systemImage: String, isMissing: Bool) {
        func timer(_ id: UUID) -> String? { project.timers.first { $0.id == id }?.name }
        func quoted(_ name: String?) -> String { name.map { "“\($0)”" } ?? "(deleted)" }
        switch self {
        case .startTimer(let id): return ("Start \(quoted(timer(id)))", "play.fill", timer(id) == nil)
        case .stopTimer(let id): return ("Pause \(quoted(timer(id)))", "pause.fill", timer(id) == nil)
        case .resetTimer(let id): return ("Reset \(quoted(timer(id)))", "arrow.counterclockwise", timer(id) == nil)
        case .restartTimer(let id): return ("Restart \(quoted(timer(id)))", "arrow.clockwise", timer(id) == nil)
        case .showMessage(let id, _):
            let name = project.message(withID: id)?.name
            return ("Show message \(quoted(name))", "text.bubble", name == nil)
        case .clearMessages: return ("Clear messages", "xmark.circle", false)
        case .showProp(let id):
            let name = project.prop(withID: id).map { $0.label ?? "Prop" }
            return ("Show prop \(quoted(name))", "square.on.square", name == nil)
        case .hideProp(let id):
            let name = project.prop(withID: id).map { $0.label ?? "Prop" }
            return ("Hide prop \(quoted(name))", "square.on.square.dashed", name == nil)
        case .clearProps: return ("Clear props", "xmark.circle", false)
        case .showStageMessage: return ("Stage message", "rectangle.on.rectangle", false)
        case .hideStageMessage: return ("Hide the stage message", "rectangle.on.rectangle.slash", false)
        case .setStageLayout(let id?):
            let name = project.stageLayout(withID: id).map { $0.name.isEmpty ? "Untitled" : $0.name }
            return ("Stage layout \(quoted(name))", "rectangle.3.group", name == nil)
        case .setStageLayout(nil): return ("Stage layout “Standard”", "rectangle.3.group", false)
        case .playAudio(let track):
            let name = project.asset(withID: track.assetID)?.originalFilename
            return ("Play \(quoted(name))", "music.note", name == nil)
        case .stopAudio: return ("Stop audio", "speaker.slash", false)
        case .clearSlide: return ("Clear slide", "xmark.rectangle", false)
        case .clearBackground: return ("Clear background", "xmark.rectangle", false)
        case .clearAll: return ("Clear all", "xmark.rectangle.fill", false)
        case .blackout: return ("Blackout", "moon.fill", false)
        case .runMacro(let id):
            let name = project.macro(withID: id)?.name
            return ("Run macro \(quoted(name))", "square.grid.2x2", name == nil)
        }
    }
}

/// Edits a list of actions: each in words, with its own settings (a message's blanks, a stage message's text), in
/// order. Used for a slide's actions and a macro's.
struct ActionListEditor: View {
    let project: ProjectDocument
    let actions: [ShowAction]
    /// Macros can clear the output, black out and play audio; slides can't.
    var isForMacro = false
    /// The macro being edited, which can't run itself.
    var macroID: UUID?
    let onChange: ([ShowAction]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if actions.isEmpty {
                Text(isForMacro ? "No actions yet." : "None.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                row(action, at: index)
            }
            AddActionMenu(project: project, isForMacro: isForMacro, macroID: macroID) { action in
                onChange(actions + [action])
            }
        }
    }

    private func row(_ action: ShowAction, at index: Int) -> some View {
        let summary = action.summary(in: project)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: summary.isMissing ? "exclamationmark.triangle.fill" : summary.systemImage)
                    .foregroundStyle(summary.isMissing ? Palette.warning : .secondary)
                    .frame(width: 18)
                Text(summary.text)
                    .lineLimit(2)
                    .help(summary.isMissing ? "What this pointed at was deleted, so it does nothing." : summary.text)
                Spacer(minLength: 0)
                RowMenuButton(subject: summary.text) {
                    Button("Move Up") { move(index, by: -1) }
                        .disabled(index == 0)
                    Button("Move Down") { move(index, by: 1) }
                        .disabled(index == actions.count - 1)
                    Divider()
                    Button("Remove", role: .destructive) { replace(index, with: nil) }
                }
            }
            settings(action, at: index)
                .padding(.leading, 18 + Spacing.sm)
        }
    }

    @ViewBuilder
    private func settings(_ action: ShowAction, at index: Int) -> some View {
        switch action {
        case .showMessage(let messageID, let values):
            ForEach(project.message(withID: messageID)?.fields ?? [], id: \.self) { field in
                TextField(field, text: Binding(
                    get: { values[field] ?? "" },
                    set: { value in
                        var updated = values
                        updated[field] = value
                        replace(index, with: .showMessage(messageID: messageID, values: updated))
                    }
                ), prompt: Text(field))
                .textFieldStyle(.roundedBorder)
            }
        case .showStageMessage(let text):
            TextField("Stage message", text: Binding(
                get: { text },
                set: { replace(index, with: .showStageMessage(text: $0)) }
            ), prompt: Text("e.g. Next: the offering"))
            .textFieldStyle(.roundedBorder)
        case .playAudio(let track):
            Toggle("Loop", isOn: Binding(
                get: { track.loops },
                set: { loops in
                    var updated = track
                    updated.loops = loops
                    replace(index, with: .playAudio(track: updated))
                }
            ))
        default:
            EmptyView()
        }
    }

    private func replace(_ index: Int, with action: ShowAction?) {
        var updated = actions
        if let action { updated[index] = action } else { updated.remove(at: index) }
        onChange(updated)
    }

    private func move(_ index: Int, by offset: Int) {
        var updated = actions
        updated.swapAt(index, index + offset)
        onChange(updated)
    }
}

/// The menu of actions to add, grouped by what they act on. Lists only what the project has.
struct AddActionMenu: View {
    let project: ProjectDocument
    let isForMacro: Bool
    let macroID: UUID?
    let onAdd: (ShowAction) -> Void

    var body: some View {
        Menu {
            Menu("Timer") {
                if project.timers.isEmpty { Text("No timers") }
                ForEach(project.timers) { timer in
                    Menu(timer.name) {
                        Button("Start") { onAdd(.startTimer(timerID: timer.id)) }
                        Button("Pause") { onAdd(.stopTimer(timerID: timer.id)) }
                        Button("Reset") { onAdd(.resetTimer(timerID: timer.id)) }
                        Button("Restart") { onAdd(.restartTimer(timerID: timer.id)) }
                    }
                }
            }
            Menu("Message") {
                ForEach(project.messages) { message in
                    Button("Show “\(message.name)”") { onAdd(.showMessage(messageID: message.id, values: [:])) }
                }
                if !project.messages.isEmpty { Divider() }
                Button("Clear Messages") { onAdd(.clearMessages) }
            }
            Menu("Prop") {
                ForEach(project.props.slides) { prop in
                    Menu(prop.label ?? "Prop") {
                        Button("Show") { onAdd(.showProp(propID: prop.id)) }
                        Button("Hide") { onAdd(.hideProp(propID: prop.id)) }
                    }
                }
                if !project.props.slides.isEmpty { Divider() }
                Button("Clear Props") { onAdd(.clearProps) }
            }
            Menu("Stage Display") {
                Button("Stage Message") { onAdd(.showStageMessage(text: "")) }
                Button("Hide the Stage Message") { onAdd(.hideStageMessage) }
                Divider()
                Button("Layout: Standard") { onAdd(.setStageLayout(layoutID: nil)) }
                ForEach(project.stageLayouts) { layout in
                    Button("Layout: \(layout.name.isEmpty ? "Untitled" : layout.name)") { onAdd(.setStageLayout(layoutID: layout.id)) }
                }
            }
            Menu("Audio") {
                if isForMacro {
                    ForEach(project.mediaAssets.filter { $0.kind == .audio }) { asset in
                        Button("Play “\(asset.originalFilename)”") { onAdd(.playAudio(track: AudioTrack(assetID: asset.id))) }
                    }
                    Divider()
                }
                Button("Stop Audio") { onAdd(.stopAudio) }
            }
            if isForMacro {
                Menu("Output") {
                    Button("Clear Slide") { onAdd(.clearSlide) }
                    Button("Clear Background") { onAdd(.clearBackground) }
                    Button("Clear All") { onAdd(.clearAll) }
                    Button("Blackout") { onAdd(.blackout) }
                }
            }
            Menu("Macro") {
                let macros = project.macros.filter { $0.id != macroID }
                if macros.isEmpty { Text("No other macros") }
                ForEach(macros) { macro in
                    Button("Run “\(macro.name)”") { onAdd(.runMacro(macroID: macro.id)) }
                }
            }
        } label: {
            Label("Add Action", systemImage: "plus")
        }
        .fixedSize()
    }
}

/// On a slide's thumbnail: it runs actions when taken live.
struct ActionsMark: View {
    let count: Int

    var body: some View {
        Image(systemName: "bolt.fill")
            .foregroundStyle(.secondary)
            .help(count == 1 ? "Runs an action when taken live" : "Runs \(count) actions when taken live")
            .accessibilityLabel(count == 1 ? "Runs an action" : "Runs \(count) actions")
    }
}
