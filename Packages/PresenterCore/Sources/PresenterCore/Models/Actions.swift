import Foundation

/// Something the show does at a cue, like ProPresenter's slide actions: start a timer, show a message or a prop, change
/// the stage display. A slide runs its actions when it's taken live; a macro runs a named list of them at a click.
/// Actions that point at a timer, message, prop, layout, audio file or macro that's gone do nothing.
public enum ShowAction: Codable, Hashable, Sendable {
    case startTimer(timerID: UUID)
    case stopTimer(timerID: UUID)
    case resetTimer(timerID: UUID)
    /// Reset, then start: a countdown begins again from its full time.
    case restartTimer(timerID: UUID)
    /// Shows a message with its blanks filled in.
    case showMessage(messageID: UUID, values: [String: String])
    case clearMessages
    case showProp(propID: UUID)
    case hideProp(propID: UUID)
    case clearProps
    case showStageMessage(text: String)
    case hideStageMessage
    /// Nil is the standard stage look.
    case setStageLayout(layoutID: UUID?)
    case playAudio(track: AudioTrack)
    case stopAudio
    case clearSlide
    case clearBackground
    case clearAll
    case blackout
    case runMacro(macroID: UUID)

    /// Whether it makes sense on a slide. Clearing or blacking out the slide just taken live would undo the take, and
    /// slides have their own audio cue.
    public var isAllowedOnSlides: Bool {
        switch self {
        case .clearSlide, .clearAll, .blackout, .playAudio: false
        default: true
        }
    }
}

/// A named, reusable list of actions, run from the Macros tab or by a slide: "Pre-Service" might show the logo prop,
/// start the countdown and play the walk-in music.
public struct Macro: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Its button's colour. Nil is the standard button.
    public var color: RGBAColor?
    public var actions: [ShowAction]

    public init(id: UUID = UUID(), name: String, color: RGBAColor? = nil, actions: [ShowAction] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.actions = actions
    }
}

extension ShowAction {
    /// The audio file it plays, if any.
    public var audioAssetID: UUID? {
        if case .playAudio(let track) = self { return track.assetID }
        return nil
    }
}

extension ProjectDocument {
    public func macro(withID macroID: UUID) -> Macro? {
        macros.first { $0.id == macroID }
    }

    /// Macros that play the audio file, so deleting it can say what it's used by.
    public func macrosUsing(asset assetID: UUID) -> [Macro] {
        macros.filter { $0.actions.contains { $0.audioAssetID == assetID } }
    }
}
