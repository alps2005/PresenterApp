import Foundation
import Observation
import PresenterCore

/// Runs the live slide's countdown (see `PresentationCoordinator+AutoAdvance`): one task sleeps until the deadline,
/// then moves the slide on. It starts over whenever the countdown changes, and nothing runs while no slide counts down.
final class AutoAdvanceDriver {
    private let coordinator: PresentationCoordinator
    private let playback: MediaPlaybackController
    private let mediaLibrary: MediaLibrary
    private var task: Task<Void, Never>?

    init(coordinator: PresentationCoordinator, playback: MediaPlaybackController, mediaLibrary: MediaLibrary) {
        self.coordinator = coordinator
        self.playback = playback
        self.mediaLibrary = mediaLibrary
        follow()
    }

    private func follow() {
        let advance = withObservationTracking {
            let advance = coordinator.state.autoAdvance
            // Waiting on a video also watches the player, the live background and missing files.
            if case .waitingForVideo = advance?.phase {
                _ = (playback.assetID, playback.hasFinished, coordinator.state.liveBackground, mediaLibrary.missing)
            }
            return advance
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        task?.cancel()
        task = nil
        guard let advance else { return }
        switch advance.phase {
        case .waitingForVideo(let assetID):
            if videoIsOver(assetID) { coordinator.videoDidFinish(assetID) }
        case .counting(_, let deadline):
            task = Task { [weak self] in
                while !Task.isCancelled {
                    let delay = deadline.timeIntervalSinceNow
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard !Task.isCancelled, let self else { return }
                    // Done once the slide moves, or the countdown changed under us; otherwise it woke a hair early.
                    if coordinator.advanceIfDue() || coordinator.state.autoAdvance?.phase != advance.phase { return }
                }
            }
        }
    }

    /// True when there's no more video to wait for: it ended, it's no longer the live background (cleared or
    /// replaced), or its file is missing. A video the player hasn't loaded yet is still to come.
    private func videoIsOver(_ assetID: UUID) -> Bool {
        guard case .video(let video) = coordinator.state.liveBackground, video.assetID == assetID else { return true }
        if mediaLibrary.isMissing(assetID) { return true }
        return playback.assetID == assetID && playback.hasFinished
    }
}
