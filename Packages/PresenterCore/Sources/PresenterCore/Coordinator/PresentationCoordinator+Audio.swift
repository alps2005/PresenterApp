import Foundation

// Audio: tracks played from the audio bin, slide audio cues and presentation soundtracks. Playing and stopping
// are live commands, never undone; setting cues and soundtracks are undoable edits.
extension PresentationCoordinator {
    /// How long Stop Audio and Clear All take to fade a track out.
    public static let defaultAudioFadeOut: Double = 2

    // MARK: - Live

    /// Starts a track from the top, fading out whatever was playing.
    @discardableResult
    public func playAudio(_ track: AudioTrack) -> CommandResult {
        guard isAudio(track.assetID) else { return reject(.unknownMediaAsset) }
        state.audio = LiveAudio(track: track)
        Log.coordinator.info("Audio: play \(track.assetID, privacy: .public)")
        return applied()
    }

    /// Pauses the playing track, or carries on with a paused one.
    @discardableResult
    public func toggleAudioPause() -> CommandResult {
        guard state.audio != nil else { return reject(.noAudio) }
        state.audio?.isPaused.toggle()
        return applied()
    }

    /// Fades the playing track out over `fadeOut` seconds (0 stops it at once).
    @discardableResult
    public func stopAudio(fadeOut: Double = defaultAudioFadeOut) -> CommandResult {
        guard state.audio != nil else { return reject(.noAudio) }
        state.audioStopFade = max(fadeOut, 0)
        state.audio = nil
        Log.coordinator.info("Audio: stop")
        return applied()
    }

    /// The player reports that a track that doesn't loop reached its end. Ignored if another start has replaced it.
    public func audioDidFinish(startID: UUID) {
        guard state.audio?.startID == startID else { return }
        state.audioStopFade = 0
        state.audio = nil
    }

    /// Carries out the audio of a slide just taken live. Taking the same slide live again changes nothing, so
    /// fixing a typo never restarts the music. A slide's own cue comes first; otherwise moving into a presentation
    /// from another item starts its soundtrack, unless that track is already playing.
    func cueAudio(for position: SlidePosition, after previous: SlidePosition?) {
        guard position != previous, let presentation = project.presentation(forItem: position.itemID) else { return }
        switch presentation.slide(withID: position.slideID)?.audioCue {
        case .play(let track):
            // A cue for the track already playing (a chorus that comes round again) lets it play on.
            if let live = state.audio, live.track.assetID == track.assetID, !live.isPaused { return }
            if isAudio(track.assetID) { state.audio = LiveAudio(track: track) }
        case .stop(let fadeOut):
            if state.audio != nil { stopAudio(fadeOut: fadeOut) }
        case nil:
            guard position.itemID != previous?.itemID, let soundtrack = presentation.soundtrack,
                  state.audio?.track.assetID != soundtrack.assetID, isAudio(soundtrack.assetID) else { return }
            state.audio = LiveAudio(track: soundtrack)
        }
    }

    private func isAudio(_ assetID: UUID) -> Bool {
        project.asset(withID: assetID)?.kind == .audio
    }

    // MARK: - Editing

    /// Sets what a slide does to the audio when it's taken live. Nil leaves the audio alone.
    @discardableResult
    public func setAudioCue(_ cue: AudioCue?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Audio Cue", coalescing: "audio-cue-\(slideID)") {
            if let assetID = cue?.assetID, !isAudio(assetID) { return reject(.unknownMediaAsset) }
            return editSlide(slideID, inPresentation: presentationID) { $0.audioCue = cue }
        }
    }

    /// Sets the track a presentation plays when the operator moves into it. Nil plays none.
    @discardableResult
    public func setSoundtrack(_ track: AudioTrack?, presentationID: UUID) -> CommandResult {
        recordingUndo("Soundtrack", coalescing: "soundtrack-\(presentationID)") {
            if let track, !isAudio(track.assetID) { return reject(.unknownMediaAsset) }
            return editPresentation(presentationID) { $0.soundtrack = track }
        }
    }
}
