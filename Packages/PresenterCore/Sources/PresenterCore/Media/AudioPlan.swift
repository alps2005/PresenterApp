import Foundation

/// What the audio player should do when the live audio changes. UI-free: the app's audio controller owns the
/// players and carries out the decision.
public enum AudioDecision: Equatable, Sendable {
    /// Nothing playing and nothing to play.
    case idle
    /// The same start carries on (pausing and resuming are the player's to follow).
    case keep
    /// Nothing is playing: the track starts, fading in if it asks to.
    case start(LiveAudio)
    /// Another track is playing: it fades out over `fadeOut` seconds while the new one starts.
    case crossfade(LiveAudio, fadeOut: Double)
    /// The audio was stopped: what's playing fades out over this many seconds (0 stops at once).
    case fadeOut(Double)
    /// The track's file is gone (or the asset isn't in the project). What's playing stops and the operator is warned.
    case missing(UUID)
}

public enum AudioPlan {
    /// The shortest fade from one track to the next, so changing tracks never clicks.
    public static let minimumCrossfade: Double = 0.5

    /// - Parameters:
    ///   - playingStartID: the start playing now, if any (see `LiveAudio.startID`).
    ///   - live: the live audio.
    ///   - stopFade: the fade the last stop asked for (`PresentationState.audioStopFade`).
    ///   - fileExists: whether an asset's file can be played; only asked for a track that isn't already playing.
    public static func decide(
        playingStartID: UUID?,
        live: LiveAudio?,
        stopFade: Double,
        fileExists: (UUID) -> Bool
    ) -> AudioDecision {
        guard let live else { return playingStartID == nil ? .idle : .fadeOut(max(stopFade, 0)) }
        if live.startID == playingStartID { return .keep }
        guard fileExists(live.track.assetID) else { return .missing(live.track.assetID) }
        guard playingStartID != nil else { return .start(live) }
        return .crossfade(live, fadeOut: max(live.track.fadeIn, minimumCrossfade))
    }

    /// The volume, 0 to 1, `elapsed` seconds into a fade from `from` to `to` that lasts `duration`. A curve that
    /// follows loudness as heard, so a fade sounds even rather than dropping away at the end.
    public static func fadeVolume(from: Double, to: Double, elapsed: Double, duration: Double) -> Double {
        guard duration > 0, elapsed < duration else { return to }
        let progress = max(elapsed, 0) / duration
        let eased = progress * progress * (3 - 2 * progress)
        return from + (to - from) * eased
    }
}
