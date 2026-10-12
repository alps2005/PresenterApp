import SwiftUI
import PresenterCore

struct ControlBar: View {
    let coordinator: PresentationCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Button { coordinator.previousSlide() } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .help("Previous slide (← or ⌥⌘←)")

            Button { coordinator.nextSlide() } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .help("Next slide (→, Space or ⌥⌘→)")

            Button { coordinator.takeLive() } label: {
                Label("Take Live", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(coordinator.state.preview == nil)
            .help("Send the cued slide to the audience (Return or ⌘Return)")

            Divider().frame(height: 22)

            Button { coordinator.clearOutput() } label: {
                Label("Clear", systemImage: "xmark.rectangle")
            }
            .disabled(coordinator.state.live == nil)
            .help("Remove the slide from the audience output (⌥⌘C)")

            Button { coordinator.blackout() } label: {
                Label("Blackout", systemImage: "rectangle.fill")
            }
            .disabled(coordinator.state.isBlackout)
            .help("Show pure black on the audience output (⌥⌘B)")

            Button { coordinator.restoreOutput() } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .disabled(!coordinator.canRestore)
            .help("Lift blackout and bring back a cleared slide (⌥⌘R)")

            Spacer()

            if let rejection = coordinator.lastRejection {
                Label(rejection.message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
