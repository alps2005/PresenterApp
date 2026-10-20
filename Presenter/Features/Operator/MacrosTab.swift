import PresenterCore
import SwiftUI

/// Buttons that run macros: named lists of actions such as "Pre-Service" (logo, countdown, walk-in music) or "End"
/// (clear everything). Macros are made and changed in a sheet, so the live panel keeps no text fields.
struct MacrosTab: View {
    let coordinator: PresentationCoordinator
    @State private var editingID: UUID?
    @State private var pendingDeletion: Macro?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(coordinator.project.macros) { macro in
                    button(macro)
                }
            }
            Button {
                editingID = coordinator.addMacro(named: "Macro \(coordinator.project.macros.count + 1)").id
            } label: {
                Label("New Macro", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            Text("A macro does several things at one click: show a prop, start a timer, play music, change the stage display. Slides can run them too, in the slide editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: Binding(get: { editingID.map(EditedMacro.init) }, set: { editingID = $0?.id })) { edited in
            MacroEditorSheet(coordinator: coordinator, macroID: edited.id)
        }
        .confirmDeletion("Delete “\(pendingDeletion?.name ?? "")”?",
                         message: "Slides and macros that run it will skip it. You can undo this.",
                         of: $pendingDeletion) { macro in
            coordinator.deleteMacro(macro.id)
        }
    }

    private struct EditedMacro: Identifiable {
        let id: UUID
    }

    private func button(_ macro: Macro) -> some View {
        Button {
            coordinator.runMacro(macro.id)
        } label: {
            Text(macro.name.isEmpty ? "Untitled Macro" : macro.name)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(macro.color?.color ?? Palette.panelRaised)
        .help(macro.actions.isEmpty ? "No actions yet. Right-click to edit." : macro.actions
            .map { $0.summary(in: coordinator.project).text }.joined(separator: "\n"))
        .contextMenu {
            Button("Run") { coordinator.runMacro(macro.id) }
            Button("Edit…") { editingID = macro.id }
            Button("Duplicate") { coordinator.duplicateMacro(macro.id) }
            Divider()
            Button("Delete…", role: .destructive) { pendingDeletion = macro }
        }
    }
}

/// Names a macro, colours its button and lists what it does. Changes save as they're made and undo with ⌘Z.
struct MacroEditorSheet: View {
    let coordinator: PresentationCoordinator
    let macroID: UUID
    @Environment(\.dismiss) private var dismiss

    private var macro: Macro? { coordinator.project.macro(withID: macroID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Edit Macro").font(.title2.bold())
            if let macro {
                HStack {
                    TextField("Name", text: Binding(get: { macro.name }, set: { name in update { $0.name = name } }))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Colour", isOn: Binding(
                        get: { macro.color != nil },
                        set: { on in update { $0.color = on ? RGBAColor(red: 0.2, green: 0.45, blue: 0.85) : nil } }
                    ))
                    if let color = macro.color {
                        ColorPicker("Colour", selection: Binding(get: { color.color }, set: { new in update { $0.color = RGBAColor(new) } }),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                Text("Actions run in this order.").font(.subheadline.bold())
                ScrollView {
                    ActionListEditor(project: coordinator.project, actions: macro.actions, isForMacro: true, macroID: macro.id) { actions in
                        update { $0.actions = actions }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200, maxHeight: 360)
            } else {
                Text("This macro was deleted.").foregroundStyle(.secondary)
            }
            HStack {
                Button("Run Now") { coordinator.runMacro(macroID) }
                    .disabled(macro?.actions.isEmpty ?? true)
                    .help("Runs it on the outputs now")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 480)
    }

    private func update(_ change: (inout Macro) -> Void) {
        guard var updated = macro else { return }
        change(&updated)
        coordinator.updateMacro(updated)
    }
}
