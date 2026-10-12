import SwiftUI
import PresenterCore

/// Menu bar commands. Live shortcuts use ⌥⌘ so they never collide with text editing;
/// plain arrow/space/return keys work when the slide grid has focus.
struct PresenterCommands: Commands {
    let coordinator: PresentationCoordinator
    let outputManager: OutputManager

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
        }

        CommandMenu("Live") {
            Button("Take Live") { coordinator.takeLive() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Next Slide") { coordinator.nextSlide() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Slide") { coordinator.previousSlide() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Clear Output") { coordinator.clearOutput() }
                .keyboardShortcut("c", modifiers: [.command, .option])
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
        }
    }
}
