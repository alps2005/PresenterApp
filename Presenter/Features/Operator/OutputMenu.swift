import PresenterCore
import SwiftUI

/// Toolbar control that shows output health and chooses where the audience outputs and the stage display go, and
/// what each audience output shows.
struct OutputMenu: View {
    let outputManager: OutputManager
    /// Opens the look editor for an audience output.
    let onEditLook: (OutputRole) -> Void

    var body: some View {
        Menu {
            Section(OutputRole.audience.title) { section(.audience) }
            Divider()
            Menu(OutputRole.secondAudience.title) { section(.secondAudience) }
            Menu(OutputRole.stage.title) { section(.stage) }
        } label: {
            if status.isWarning {
                Label(status.text, systemImage: status.systemImage).foregroundStyle(Palette.warning)
            } else {
                Label(status.text, systemImage: status.systemImage)
            }
        }
        // The toolbar shows only the icon, so the status text is here too.
        .help(status.text)
    }

    @ViewBuilder
    private func section(_ role: OutputRole) -> some View {
        Button("Show in Window") { outputManager.show(.windowed, for: role) }

        Section("Full Screen") {
            let candidates = outputManager.fullScreenCandidates(role)
            let inUse = outputManager.displaysInUse(byOtherThan: role)
            if candidates.isEmpty && inUse.isEmpty {
                Text("Connect another display for full-screen output")
            }
            ForEach(candidates) { display in
                Button("\(display.name) (\(display.resolutionDescription))") {
                    outputManager.show(.display(display.id), for: role)
                }
            }
            // Two outputs never share a screen; say which one has it rather than leaving it out.
            ForEach(inUse) { display in
                Button("\(display.name) – used by the \(outputManager.role(otherThan: role, on: display)?.title ?? "another output")") {}
                    .disabled(true)
            }
        }

        if role.isAudience {
            Divider()
            Button(outputManager.look(role).isEverything ? "Look…" : "Look… (customized)") { onEditLook(role) }
        }
        Divider()
        Button(hideTitle(role)) { outputManager.hide(role) }
            .disabled(!outputManager.isEnabled(role))
    }

    private func hideTitle(_ role: OutputRole) -> String {
        switch role {
        case .audience: "Hide Output"
        case .secondAudience: "Hide Second Output"
        case .stage: "Hide Stage Display"
        }
    }

    /// The audience output's state, unless an output is waiting for its display: that warning wins.
    private var status: (text: String, systemImage: String, isWarning: Bool) {
        if let waiting = waitingText(outputManager.status) {
            return (waiting, "exclamationmark.triangle.fill", true)
        }
        for role in [OutputRole.secondAudience, .stage] {
            if let waiting = waitingText(outputManager.status(role)) {
                return ("\(role.title): \(waiting)", "exclamationmark.triangle.fill", true)
            }
        }
        switch outputManager.status {
        case .off: return ("Output Off", "display", false)
        case .windowed: return ("Output: Window", "macwindow", false)
        case .fullScreen(let name): return ("Output: \(name)", "display", false)
        case .displayMissing, .displayHasOperatorWindow: return ("Output Off", "display", false)
        }
    }

    /// Why an output is hidden although it's on: its display is gone or has the operator window.
    private func waitingText(_ status: OutputStatus) -> String? {
        switch status {
        case .displayMissing(let name): "\(name) disconnected"
        case .displayHasOperatorWindow(let name): "\(name) has the operator window"
        case .off, .windowed, .fullScreen: nil
        }
    }
}
