import Foundation

/// Moves the live slide on by itself after a while, like ProPresenter's Go To Next Timer. It overrides the
/// presentation's Slideshow interval for its slide.
public struct GoToNextTimer: Codable, Hashable, Sendable {
    /// How long the slide stays up. 0 moves on at once (or as soon as the slide's video ends).
    public var seconds: Double
    /// After this slide, go back to the presentation's first slide instead of moving on to the next one.
    public var loopsToFirst: Bool

    public init(seconds: Double, loopsToFirst: Bool = false) {
        self.seconds = seconds
        self.loopsToFirst = loopsToFirst
    }
}

/// The live slide's countdown to moving on by itself. Live state: never saved and never undone.
public struct AutoAdvance: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Counting down; the slide moves on at `deadline`.
        case counting(started: Date, deadline: Date)
        /// The slide's video plays once, so the countdown starts when it ends.
        case waitingForVideo(assetID: UUID)
    }

    /// The live slide the countdown belongs to.
    public var position: SlidePosition
    public var seconds: Double
    public var phase: Phase

    /// How far the countdown has run, from 0 to 1. Nil while waiting for the video.
    public func progress(at date: Date) -> Double? {
        guard case .counting(let started, let deadline) = phase else { return nil }
        let total = deadline.timeIntervalSince(started)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(started) / total, 0), 1)
    }

    /// Seconds left, rounded up. Nil while waiting for the video.
    public func secondsLeft(at date: Date) -> Int? {
        guard case .counting(_, let deadline) = phase else { return nil }
        return max(0, Int(deadline.timeIntervalSince(date).rounded(.up)))
    }
}
