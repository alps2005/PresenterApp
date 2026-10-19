import Foundation

/// A track to play: an audio file from the media library, how it starts and whether it loops.
public struct AudioTrack: Codable, Hashable, Sendable {
    public var assetID: UUID
    public var loops: Bool
    /// Seconds to fade in from silence. 0 starts at full volume.
    public var fadeIn: Double

    public static let fadeRange: ClosedRange<Double> = 0...10

    public init(assetID: UUID, loops: Bool = false, fadeIn: Double = 0) {
        self.assetID = assetID
        self.loops = loops
        self.fadeIn = fadeIn
    }
}

/// What a slide does to the audio when it's taken live. A slide without a cue leaves the audio alone.
public enum AudioCue: Codable, Hashable, Sendable {
    case play(AudioTrack)
    /// Fades out whatever is playing over this many seconds; 0 stops it at once.
    case stop(fadeOut: Double)

    public var assetID: UUID? {
        if case .play(let track) = self { return track.assetID }
        return nil
    }
}

/// The track playing for the audience. Not saved: like the live slide, audio starts silent at launch.
public struct LiveAudio: Equatable, Sendable {
    public var track: AudioTrack
    /// New each time the track is started, so starting the same track again starts it from the top.
    public var startID: UUID
    public var isPaused: Bool

    public init(track: AudioTrack, startID: UUID = UUID(), isPaused: Bool = false) {
        self.track = track
        self.startID = startID
        self.isPaused = isPaused
    }
}
