import Foundation
import Observation

/// Operator and output state, kept deliberately separate:
/// - **selected**: the playlist item the operator is looking at / editing.
/// - **preview**: the slide cued to go live next time the operator takes it.
/// - **live**: what the audience sees, as a snapshot so later edits don't leak to the output.
///
/// An observable class rather than a struct, so views follow each property on its own: selecting an item while
/// scrolling doesn't redraw the outputs and every thumbnail. Only the coordinator changes it.
@MainActor
@Observable
public final class PresentationState {
    public internal(set) var selectedItemID: UUID?
    public internal(set) var preview: SlidePosition?
    public internal(set) var live: LiveSlide?
    /// The slide removed by `clearOutput()`, kept so `restoreOutput()` can bring it back.
    public internal(set) var cleared: LiveSlide?
    /// Blackout overrides everything on the audience output until restored.
    public internal(set) var isBlackout: Bool
    /// The background layer on the audience output, under the live slide. Nil shows the app's default
    /// background. A slide with a transparent background leaves it as it is when taken live.
    public internal(set) var liveBackground: SlideBackground?
    /// The background removed by `clearBackground()`, kept so `restoreOutput()` can bring it back.
    public internal(set) var clearedBackground: SlideBackground?
    /// A message to the people on stage, shown only on the stage display.
    public internal(set) var stageMessage: String?
    /// The message over the slides on the audience output, and the one Clear Messages removed.
    public internal(set) var activeMessage: ActiveMessage?
    public internal(set) var clearedMessage: ActiveMessage?
    /// Props on the audience output, in the order they were shown (later ones draw on top), and the ones
    /// Clear Props removed.
    public internal(set) var activeProps: [UUID] = []
    public internal(set) var clearedProps: [UUID] = []
    /// Each shown prop as it was when shown. Editing a prop never changes what the audience sees until it's
    /// shown again, like a slide that has to be taken live again.
    public internal(set) var propSnapshots: [UUID: SlideDocument] = [:]
    /// The live slide's countdown to moving on by itself, if it has one.
    public internal(set) var autoAdvance: AutoAdvance?

    public init(
        selectedItemID: UUID? = nil,
        preview: SlidePosition? = nil,
        live: LiveSlide? = nil,
        cleared: LiveSlide? = nil,
        isBlackout: Bool = false,
        liveBackground: SlideBackground? = nil,
        clearedBackground: SlideBackground? = nil
    ) {
        self.selectedItemID = selectedItemID
        self.preview = preview
        self.live = live
        self.cleared = cleared
        self.isBlackout = isBlackout
        self.liveBackground = liveBackground
        self.clearedBackground = clearedBackground
    }
}

/// A slide with everything the renderer needs resolved, such as the background it inherits.
public struct RenderedSlide: Equatable, Sendable {
    public var slide: SlideDocument
    /// The slide's own background, else its presentation's. Nil means the app's default background.
    public var background: SlideBackground?

    public init(slide: SlideDocument, background: SlideBackground? = nil) {
        self.slide = slide
        self.background = background
    }
}

/// A slide on the audience output, captured at the moment it was taken live. The background is
/// captured too, so changing a presentation's background doesn't leak onto the output.
public struct LiveSlide: Equatable, Sendable {
    public var position: SlidePosition
    public var rendered: RenderedSlide

    public init(position: SlidePosition, rendered: RenderedSlide) {
        self.position = position
        self.rendered = rendered
    }

    public var slide: SlideDocument { rendered.slide }
}

/// What the audience renderer should draw. Derived from `PresentationState`, never stored.
public enum AudienceScene: Equatable, Sendable {
    case black
    /// Nothing on either layer: the app's default background.
    case empty
    /// A background with no slide on it, e.g. after Clear Slide.
    case background(SlideBackground)
    /// A slide over its background. On the audience output the background is the background layer.
    case slide(RenderedSlide)
}

public enum CommandResult: Equatable, Sendable {
    case applied
    case rejected(CommandRejection)

    public var isApplied: Bool { self == .applied }
}

public enum CommandRejection: Error, Equatable, Sendable {
    case unknownItem
    case unknownSlide
    case unknownPresentation
    case nothingCued
    case nothingLive
    case atEndOfPlaylist
    case atStartOfPlaylist
    /// The live slide was deleted from the playlist, or another show was opened, so there is no sequence to move along.
    case liveSlideMissing
    case nothingToRestore
    case nothingToClear
    case unknownArrangement
    case unknownTimer
    case unknownMessage
    case unknownProp
    /// A background or image referenced a media asset that isn't in the project.
    case unknownMediaAsset
    case unknownElement
    case unknownTheme
    case autoAdvanceOff
    case unknownFolder
    case unknownShow
    /// A project always has a show to open.
    case lastShow

    public var message: String {
        switch self {
        case .unknownItem: "That playlist item no longer exists."
        case .unknownSlide: "That slide no longer exists."
        case .unknownPresentation: "That presentation no longer exists."
        case .nothingCued: "Nothing is cued. Click a slide first."
        case .nothingLive: "Nothing is live."
        case .atEndOfPlaylist: "Already at the last slide."
        case .atStartOfPlaylist: "Already at the first slide."
        case .liveSlideMissing: "The live slide isn't in the open show anymore. Take a slide live to continue."
        case .nothingToRestore: "Output is already showing normally."
        case .nothingToClear: "Only the default background is showing."
        case .unknownArrangement: "That arrangement no longer exists."
        case .unknownTimer: "That timer no longer exists."
        case .unknownMessage: "That message no longer exists."
        case .unknownProp: "That prop no longer exists."
        case .unknownMediaAsset: "That image isn't in the project's media library."
        case .unknownElement: "That item is no longer on the slide."
        case .unknownTheme: "That theme no longer exists."
        case .unknownFolder: "That folder no longer exists."
        case .unknownShow: "That show no longer exists."
        case .lastShow: "This is the only show. Make another before deleting it."
        case .autoAdvanceOff: "The live slide isn't moving on by itself."
        }
    }
}
