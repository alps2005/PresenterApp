import PresenterCore
import SwiftUI

/// Toolbar control that shows output health and chooses where the audience output and the stage display go.
struct OutputMenu: View {
    let outputManager: OutputManager

    var body: some View {
        Menu {
            Section(OutputRole.audience.title) { section(.audience) }
            Divider()
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
                Button("\(display.name) – used by the \(otherRole(than: role).title)") {}
                    .disabled(true)
            }
        }

        Divider()
        Button(role == .audience ? "Hide Output" : "Hide Stage Display") { outputManager.hide(role) }
            .disabled(!outputManager.isEnabled(role))
    }

    private func otherRole(than role: OutputRole) -> OutputRole {
        OutputRole.allCases.first { $0 != role } ?? role
    }

    /// The audience output's state, unless an output has lost its display: that warning wins.
    private var status: (text: String, systemImage: String, isWarning: Bool) {
        if case .displayMissing(let name) = outputManager.status(.stage), !isAudienceMissing {
            return ("Stage display \(name) disconnected", "exclamationmark.triangle.fill", true)
        }
        switch outputManager.status {
        case .off: return ("Output Off", "display", false)
        case .windowed: return ("Output: Window", "macwindow", false)
        case .fullScreen(let name): return ("Output: \(name)", "display", false)
        case .displayMissing(let name): return ("\(name) disconnected", "exclamationmark.triangle.fill", true)
        }
    }

    private var isAudienceMissing: Bool {
        if case .displayMissing = outputManager.status { return true }
        return false
    }
}
