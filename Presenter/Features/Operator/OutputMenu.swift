import SwiftUI

/// Toolbar control that shows output health and chooses where the audience output goes.
struct OutputMenu: View {
    let outputManager: OutputManager

    var body: some View {
        Menu {
            Button("Show in Window") { outputManager.show(.windowed) }

            Section("Full Screen") {
                if outputManager.fullScreenCandidates.isEmpty {
                    Text("Connect another display for full-screen output")
                }
                ForEach(outputManager.fullScreenCandidates) { display in
                    Button("\(display.name) (\(display.resolutionDescription))") {
                        outputManager.show(.display(display.id))
                    }
                }
            }

            Divider()
            Button("Hide Output") { outputManager.hide() }
                .disabled(!outputManager.isEnabled)
        } label: {
            statusLabel
        }
        .help("Audience output")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch outputManager.status {
        case .off:
            Label("Output Off", systemImage: "display")
        case .windowed:
            Label("Output: Window", systemImage: "macwindow")
        case .fullScreen(let name):
            Label("Output: \(name)", systemImage: "display")
        case .displayMissing(let name):
            Label("\(name) disconnected", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
