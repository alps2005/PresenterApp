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
    @AppStorage("mediaBinVisible") private var isMediaBinVisible = false
    @AppStorage(Self.followSystemAppearanceKey) private var followsSystemAppearance = false
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.editorElementActions) private var editorElementActions

    static let followSystemAppearanceKey = "followSystemAppearance"

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
            // Not the selection: it changes while scrolling the workspace, and each change would rebuild the menus.
            .disabled(coordinator.project.playlist.items.isEmpty)

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
            Toggle("Media Bin", isOn: $isMediaBinVisible)
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            // The console is dark by default, for dark booths.
            Toggle("Follow System Appearance", isOn: $followsSystemAppearance)
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
            Button("Clear Messages") { coordinator.clearMessages() }
                .keyboardShortcut("g", modifiers: [.command, .option])
            Button("Clear Props") { coordinator.clearProps() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Clear All") { coordinator.clearAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Blackout") { coordinator.blackout() }
                .keyboardShortcut("b", modifiers: [.command, .option])
            Button("Restore Output") { coordinator.restoreOutput() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            // Always enabled: its state would rebuild the menus at every slide change while a Slideshow runs.
            Button("Stop Auto-Advance") { coordinator.stopAutoAdvance() }
                .keyboardShortcut(".", modifiers: [.command, .option])
        }

        CommandMenu("Output") {
            Button(outputManager.isEnabled ? "Hide Audience Output" : "Show Audience Output") {
                outputManager.toggle()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            // A checkmark item with a fixed title: when this item's title switched between Show and Hide,
            // the menu lost its shortcut once the stage display was on.
            // ⌥⌘S, not ⌥⌘D: macOS keeps ⌥⌘D for hiding the Dock, so the app would never see it.
            Toggle("Stage Display", isOn: Binding(
                get: { outputManager.isEnabled(.stage) },
                set: { _ in outputManager.toggle(.stage) }
            ))
            .keyboardShortcut("s", modifiers: [.command, .option])
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
