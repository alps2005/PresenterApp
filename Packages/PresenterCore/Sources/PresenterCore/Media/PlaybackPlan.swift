import Foundation

/// What the video player should do when the live background changes. UI-free: the app's playback controller
/// owns the AVPlayer and carries out the decision.
public enum PlaybackDecision: Equatable, Sendable {
    /// No video on the background layer.
    case stop
    /// The same video carries on without restarting (e.g. a transparent slide over it).
    case keep
    /// The same video, but its loop setting changed, so the player is set up again.
    case reload(VideoBackground)
    /// A different video starts.
    case load(VideoBackground)
    /// The video's file is gone (or the asset isn't in the project). Playback stops and the operator is warned.
    case missing(UUID)
}

public enum PlaybackPlan {
    /// - Parameters:
    ///   - playingAssetID: the video playing now, if any.
    ///   - playingLoops: whether the video playing now loops.
    ///   - background: the live background layer.
    ///   - fileExists: whether an asset's file can be played; only asked for a video that isn't already playing.
    public static func decide(
        playingAssetID: UUID?,
        playingLoops: Bool,
        background: SlideBackground?,
        fileExists: (UUID) -> Bool
    ) -> PlaybackDecision {
        guard case .video(let video) = background else { return .stop }
        if video.assetID == playingAssetID {
            return video.loops == playingLoops ? .keep : .reload(video)
        }
        return fileExists(video.assetID) ? .load(video) : .missing(video.assetID)
    }

    /// Where a looping video is within its clip: a looping player's time keeps counting past the end.
    public static func clipTime(_ seconds: Double, duration: Double) -> Double {
        guard duration > 0, seconds.isFinite, seconds >= 0 else { return 0 }
        return seconds.truncatingRemainder(dividingBy: duration)
    }

    /// Pressing play on a non-looping video that has finished starts it again from the top.
    public static func restartsFromTop(loops: Bool, currentTime: Double, duration: Double) -> Bool {
        !loops && duration > 0 && currentTime >= duration
    }
}
