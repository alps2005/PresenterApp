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
    /// The track playing for the audience. Blackout leaves it playing; Clear All and Stop Audio fade it out.
    public internal(set) var audio: LiveAudio?
    /// How the last stop asked the playing track to fade out, in seconds.
    public internal(set) var audioStopFade: Double = 0
    /// The stage layout a slide action or macro switched to, over the project's choice until the operator picks one.
    /// Live, like the rest of this state: never saved or undone.
    public internal(set) var stageLayoutOverride: StageLayoutOverride?
    /// Verses shown over the live slide from the Scripture window, without adding a presentation, and the ones
    /// Clear Slide removed. Live, like the rest of this state: never saved or undone.
    public internal(set) var scriptureOverlay: ScriptureOverlay?
    public internal(set) var clearedScriptureOverlay: ScriptureOverlay?

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

/// A passage shown over a slide taken live, one page of verses at a time. The live slide is the base slide with the
/// current page's words added on top (see `PresentationCoordinator.showScripture`).
public struct ScriptureOverlay: Equatable, Sendable {
    /// The slide under the verses.
    public var base: SlidePosition
    /// The base slide as it was taken live, so edits to it can be noticed.
    public var baseRendered: RenderedSlide
    /// Each page's verse and reference text, with the Scripture theme's look written in.
    public var pages: [SlideDocument]
    public var index: Int
    /// The passage, like "Juan 3:16-18 · RVR".
    public var caption: String

    public init(base: SlidePosition, baseRendered: RenderedSlide, pages: [SlideDocument], index: Int = 0, caption: String) {
        self.base = base
        self.baseRendered = baseRendered
        self.pages = pages
        self.index = index
        self.caption = caption
    }
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

/// A stage layout chosen by an action for now. A nil `layoutID` is the standard look.
public struct StageLayoutOverride: Equatable, Sendable {
    public var layoutID: UUID?

    public init(layoutID: UUID?) {
        self.layoutID = layoutID
    }
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
    case noAudio
    case unknownStageLayout
    case unknownMacro
    /// A section key named a section the presentation doesn't have (e.g. B in a song without a bridge).
    case noSuchSection
    /// A passage that makes no slides.
    case noVerses

    public var message: String {
        switch self {
        case .unknownItem: Localization.text("That playlist item no longer exists.")
        case .unknownSlide: Localization.text("That slide no longer exists.")
        case .unknownPresentation: Localization.text("That presentation no longer exists.")
        case .nothingCued: Localization.text("Nothing is cued. Click a slide first.")
        case .nothingLive: Localization.text("Nothing is live.")
        case .atEndOfPlaylist: Localization.text("Already at the last slide.")
        case .atStartOfPlaylist: Localization.text("Already at the first slide.")
        case .liveSlideMissing: Localization.text("The live slide isn't in the open show anymore. Take a slide live to continue.")
        case .nothingToRestore: Localization.text("Output is already showing normally.")
        case .nothingToClear: Localization.text("Only the default background is showing.")
        case .unknownArrangement: Localization.text("That arrangement no longer exists.")
        case .unknownTimer: Localization.text("That timer no longer exists.")
        case .unknownMessage: Localization.text("That message no longer exists.")
        case .unknownProp: Localization.text("That prop no longer exists.")
        case .unknownMediaAsset: Localization.text("That image isn't in the project's media library.")
        case .unknownElement: Localization.text("That item is no longer on the slide.")
        case .unknownTheme: Localization.text("That theme no longer exists.")
        case .unknownFolder: Localization.text("That folder no longer exists.")
        case .unknownShow: Localization.text("That show no longer exists.")
        case .lastShow: Localization.text("This is the only show. Make another before deleting it.")
        case .noAudio: Localization.text("No audio is playing.")
        case .unknownStageLayout: Localization.text("That stage layout no longer exists.")
        case .unknownMacro: Localization.text("That macro no longer exists.")
        case .autoAdvanceOff: Localization.text("The live slide isn't moving on by itself.")
        case .noSuchSection: Localization.text("This presentation has no section like that.")
        case .noVerses: Localization.text("That passage has no verses to show.")
        }
    }
}
