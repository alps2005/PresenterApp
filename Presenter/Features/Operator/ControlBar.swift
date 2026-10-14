import SwiftUI
import PresenterCore

struct ControlBar: View {
    let coordinator: PresentationCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Button { coordinator.takeLive() } label: {
                Label("Take Live", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(coordinator.state.preview == nil)
            .help("Send the cued slide to the audience (Return or ⌘Return)")

            Divider().frame(height: 22)

            // Per layer, like ProPresenter: the slide's words, the background under them, or both.
            Menu {
                Button("Clear Slide  ⌥⌘C") { coordinator.clearOutput() }
                    .disabled(coordinator.state.live == nil)
                Button("Clear Background  ⌥⌘X") { coordinator.clearBackground() }
                    .disabled(coordinator.state.liveBackground == nil)
                Button("Clear Messages  ⌥⌘G") { coordinator.clearMessages() }
                    .disabled(coordinator.state.activeMessage == nil)
                Button("Clear Props  ⌥⌘P") { coordinator.clearProps() }
                    .disabled(coordinator.state.activeProps.isEmpty)
                Divider()
                Button("Clear All  ⌥⌘A") { coordinator.clearAll() }
                    .disabled(!hasAnythingToClear)
            } label: {
                Label("Clear", systemImage: "xmark.rectangle")
            } primaryAction: {
                coordinator.clearOutput()
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(!hasAnythingToClear)
            .help("Click to clear the slide, keeping its background (⌥⌘C). Use the arrow for Clear Background (⌥⌘X) or Clear All (⌥⌘A).")

            Button { coordinator.blackout() } label: {
                Label("Blackout", systemImage: "rectangle.fill")
            }
            .disabled(coordinator.state.isBlackout)
            .help("Show pure black on the audience output (⌥⌘B)")

            Button { coordinator.restoreOutput() } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .disabled(!coordinator.canRestore)
            .help("Lift blackout and bring back what was cleared (⌥⌘R)")

            Spacer()

            if let rejection = coordinator.lastRejection {
                Label(rejection.message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("→ or Space next · ← previous")
                    .foregroundStyle(.secondary)
                    .help("Move through every presentation in the playlist. ⌥⌘→ / ⌥⌘← work from anywhere.")
            }
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var hasAnythingToClear: Bool {
        let state = coordinator.state
        return state.live != nil || state.liveBackground != nil || state.activeMessage != nil || !state.activeProps.isEmpty
    }
}
