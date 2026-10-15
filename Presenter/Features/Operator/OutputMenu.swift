import PresenterCore
import SwiftUI

/// Toolbar control that shows output health and chooses where the audience output and the stage display go.
struct OutputMenu: View {
    let outputManager: OutputManager

    var body: some View {
        Menu {
            section(.audience)
            Divider()
            Menu("Stage Display") { section(.stage) }
        } label: {
            statusLabel
        }
        .help("Audience output and stage display")
    }

    @ViewBuilder
    private func section(_ role: OutputRole) -> some View {
        Button("Show in Window") { outputManager.show(.windowed, for: role) }

        Section("Full Screen") {
            let candidates = outputManager.fullScreenCandidates(role)
            if candidates.isEmpty {
                Text("Connect another display for full-screen output")
            }
            ForEach(candidates) { display in
                Button("\(display.name) (\(display.resolutionDescription))") {
                    outputManager.show(.display(display.id), for: role)
                }
            }
        }

        Divider()
        Button(role == .audience ? "Hide Output" : "Hide Stage Display") { outputManager.hide(role) }
            .disabled(!outputManager.isEnabled(role))
    }

    /// The audience output's state, unless an output has lost its display: that warning wins.
    @ViewBuilder
    private var statusLabel: some View {
        if case .displayMissing(let name) = outputManager.status(.stage), !isAudienceMissing {
            Label("Stage display \(name) disconnected", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
        } else {
            switch outputManager.status {
            case .off:
                Label("Output Off", systemImage: "display")
            case .windowed:
                Label("Output: Window", systemImage: "macwindow")
            case .fullScreen(let name):
                Label("Output: \(name)", systemImage: "display")
            case .displayMissing(let name):
                Label("\(name) disconnected", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    private var isAudienceMissing: Bool {
        if case .displayMissing = outputManager.status { return true }
        return false
    }
}
