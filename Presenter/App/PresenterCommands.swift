import AppKit
import SwiftUI
import PresenterCore

/// Menu bar commands. Live shortcuts use ⌥⌘ so they never collide with text editing;
/// plain arrow/space/return keys work when the slide grid has focus.
struct PresenterCommands: Commands {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager
    let persistence: ProjectPersistence
    let ui: OperatorUIState
    @AppStorage("quickEditVisible") private var isQuickEditVisible = false
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.editorElementActions) private var editorElementActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Presentation") {
                coordinator.addPresentation(title: "Untitled")
            }
            .keyboardShortcut("n")

            Button("New Slide") {
                if let itemID = coordinator.state.selectedItemID {
                    coordinator.addSlide(toItem: itemID)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(coordinator.selectedPresentation == nil)

            Button("New Song…") { ui.isAddingSong = true }
                .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Open Project…") { persistence.openProject() }
                .keyboardShortcut("o")
        }

        // The project autosaves; Save just writes immediately.
        CommandGroup(replacing: .saveItem) {
            Button("Save") { persistence.saveNow() }
                .keyboardShortcut("s")
            Button("Export Project…") { persistence.exportProject() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Toggle("Quick Edit", isOn: $isQuickEditVisible)
                .keyboardShortcut("e", modifiers: [.command, .option])
        }

        // Text fields and text editors undo their own typing while they have focus; everywhere else ⌘Z undoes
        // the last change to the project. Live commands (Take Live, Blackout…) are never undone.
        CommandGroup(replacing: .undoRedo) {
            Button(coordinator.undoActionName.map { "Undo \($0)" } ?? "Undo") { undo() }
                .keyboardShortcut("z")
                .disabled(!coordinator.canUndo && !focusedTextCanUndo)
            Button(coordinator.redoActionName.map { "Redo \($0)" } ?? "Redo") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!coordinator.canRedo && !focusedTextCanRedo)
        }

        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { editorElementActions?.duplicate() }
                .keyboardShortcut("d")
                .disabled(editorElementActions == nil)
        }

        // Closing the operator window leaves the app (and the audience output) running; this brings it back.
        CommandGroup(before: .windowList) {
            Button("Show Operator Window") { openWindow(id: "operator") }
                .keyboardShortcut("0")
            Divider()
        }

        CommandMenu("Live") {
            Button("Take Live") { coordinator.takeLive() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Next Slide") { coordinator.nextSlide() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Slide") { coordinator.previousSlide() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Clear Slide") { coordinator.clearOutput() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Clear Background") { coordinator.clearBackground() }
                .keyboardShortcut("x", modifiers: [.command, .option])
            Button("Clear All") { coordinator.clearAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Blackout") { coordinator.blackout() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Restore Output") { coordinator.restoreOutput() }
                .keyboardShortcut("r", modifiers: [.command, .option])
        }

        CommandMenu("Output") {
            Button(outputManager.isEnabled ? "Hide Audience Output" : "Show Audience Output") {
                outputManager.toggle()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            Button(outputManager.isEnabled(.stage) ? "Hide Stage Display" : "Show Stage Display") {
                outputManager.toggle(.stage)
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    /// The text view being typed in, if any. Its own undo history covers the typing.
    private var focusedTextView: NSTextView? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable else { return nil }
        return textView
    }

    private var focusedTextCanUndo: Bool { focusedTextView?.undoManager?.canUndo ?? false }
    private var focusedTextCanRedo: Bool { focusedTextView?.undoManager?.canRedo ?? false }

    private func undo() {
        if let undoManager = focusedTextView?.undoManager, undoManager.canUndo {
            undoManager.undo()
        } else {
            coordinator.undo()
        }
    }

    private func redo() {
        if let undoManager = focusedTextView?.undoManager, undoManager.canRedo {
            undoManager.redo()
        } else {
            coordinator.redo()
        }
    }

}
