import Foundation
import Observation

/// Owns the project and all live state. Views and output windows observe it and send commands;
/// nothing else mutates presentation state.
@MainActor
@Observable
public final class PresentationCoordinator {
    public internal(set) var project: ProjectDocument
    public internal(set) var state = PresentationState()
    /// The most recent rejected command, for surfacing to the operator. Cleared by the next applied command.
    public internal(set) var lastRejection: CommandRejection?

    /// Each timer's running state, by timer ID. Timers without an entry are stopped at zero.
    public internal(set) var timerRuns: [UUID: TimerRun] = [:]

    /// Project snapshots taken before each edit, newest last. Live commands are never recorded.
    var undoStack: [UndoEntry] = []
    var redoStack: [UndoEntry] = []
    /// Consecutive edits with the same key within `coalescingInterval` (typing, dragging a slider) undo together.
    @ObservationIgnored var coalescingKey: String?
    @ObservationIgnored var lastEditTime = Date.distantPast
    @ObservationIgnored var recordingDepth = 0
    /// The clock for coalescing, timers and edit dates. Tests replace it.
    @ObservationIgnored var now: () -> Date = { Date() }

    static let undoLimit = 100
    static let coalescingInterval: TimeInterval = 1

    struct UndoEntry {
        let project: ProjectDocument
        let actionName: String
    }

    public init(project: ProjectDocument) {
        self.project = project
        state.selectedItemID = project.playlist.items.first?.id
    }

    // MARK: - Derived state

    /// What the audience sees: the live slide over the background layer, which a transparent slide keeps.
    public var audienceScene: AudienceScene {
        if state.isBlackout { return .black }
        if let live = state.live {
            return .slide(RenderedSlide(slide: live.slide, background: state.liveBackground))
        }
        if let background = state.liveBackground { return .background(background) }
        return .empty
    }

    /// How a slide would look on the audience output if taken live now: a transparent slide is shown over
    /// the background that's on screen. Used for the Up Next preview.
    public func outputPreview(of rendered: RenderedSlide) -> RenderedSlide {
        guard rendered.background == .transparent else { return rendered }
        return RenderedSlide(slide: rendered.slide, background: state.liveBackground)
    }

    /// The slide that `nextSlide()` would take live, following playlist order.
    public var upNextPosition: SlidePosition? {
        guard let live = state.live else { return nil }
        let sequence = slideSequence()
        guard let index = Self.index(of: live.position, in: sequence), index + 1 < sequence.count else { return nil }
        return sequence[index + 1]
    }

    public var upNextSlide: RenderedSlide? {
        upNextPosition.flatMap(project.renderedSlide(at:))
    }

    /// True after Clear Background when the live slide (taken live again) or the next one has a background of its
    /// own: going live puts that background back, as in ProPresenter. Clear is for now; the slide keeps its background.
    public var clearedBackgroundReturnsWithNextSlide: Bool {
        guard state.clearedBackground != nil else { return false }
        // Mirrors goLive: transparent keeps the layer as it is, and no background means the app's default.
        func bringsBackground(_ slide: RenderedSlide?) -> Bool {
            guard let background = slide?.background else { return false }
            return background != .transparent
        }
        return bringsBackground(state.live?.rendered) || bringsBackground(upNextSlide)
    }

    public var previewSlide: RenderedSlide? {
        state.preview.flatMap(project.renderedSlide(at:))
    }

    public var selectedPresentation: PresentationDocument? {
        state.selectedItemID.flatMap(project.presentation(forItem:))
    }

    /// True when `restoreOutput()` would change the audience output.
    public var canRestore: Bool {
        state.isBlackout
            || (state.live == nil && state.cleared != nil)
            || (state.liveBackground == nil && state.clearedBackground != nil)
            || (state.activeMessage == nil && state.clearedMessage != nil)
            || (state.activeProps.isEmpty && !state.clearedProps.isEmpty)
    }

    /// Props on the audience output, bottom to top. Hidden by blackout.
    public var audienceProps: [SlideDocument] {
        guard !state.isBlackout else { return [] }
        return state.activeProps.compactMap { state.propSnapshots[$0] }
    }

    /// True when a prop on screen (or cleared, waiting to be restored) has been edited since it was shown,
    /// so the audience sees an older version until it's shown again.
    public func propHasPendingEdits(_ propID: UUID) -> Bool {
        guard let shown = state.propSnapshots[propID], let current = project.prop(withID: propID) else { return false }
        return shown != current
    }

    /// The message on the audience output, if any. Hidden by blackout.
    public var audienceMessage: (message: MessageDefinition, values: [String: String])? {
        guard !state.isBlackout, let active = state.activeMessage, let message = project.message(withID: active.messageID) else {
            return nil
        }
        return (message, active.values)
    }

    /// The message's text right now, with blanks filled in and timers at `date`.
    public func messageText(_ message: MessageDefinition, values: [String: String], at date: Date) -> String {
        message.rendered(values: values) { name in
            project.timers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                .flatMap { timerSeconds($0.id, at: date) }
                .map { TimerDefinition.format($0) }
        }
    }

    /// True when the live slide (or the background it inherits) has been edited since it was taken live,
    /// so the audience sees an older version.
    public var liveSlideHasPendingEdits: Bool {
        guard let live = state.live, var current = project.renderedSlide(at: live.position) else { return false }
        // Notes never reach the audience, so editing them leaves nothing to take live again.
        current.slide.notes = live.slide.notes
        return current != live.rendered
    }

    /// The live slide's notes as they are now. Notes never reach the audience, so edits show on the stage
    /// display and in the Live panel straight away, without taking the slide live again.
    public var liveNotes: String? {
        guard let live = state.live else { return nil }
        let notes = (project.renderedSlide(at: live.position)?.slide ?? live.slide).notes
        return notes?.isEmpty == false ? notes : nil
    }

    // MARK: - Shared helpers
    // Used by the command extensions in the other PresentationCoordinator+*.swift files.

    func goLive(at position: SlidePosition) -> CommandResult {
        guard let rendered = project.renderedSlide(at: position) else { return reject(.unknownSlide) }
        state.live = LiveSlide(position: position, rendered: rendered)
        state.cleared = nil
        // An opaque slide replaces the background layer; a transparent one leaves what's on screen.
        if rendered.background != .transparent {
            var background = rendered.background
            // The same video carries on playing, so the operator's mute choice carries on with it.
            if case .video(var next) = background, case .video(let current) = state.liveBackground,
               next.assetID == current.assetID {
                next.isMuted = current.isMuted
                background = .video(next)
            }
            state.liveBackground = background
            state.clearedBackground = nil
        }
        Log.coordinator.info("Live: item \(position.itemID, privacy: .public) slide \(position.slideID, privacy: .public)")
        return applied()
    }

    func step(by offset: Int, boundary: CommandRejection) -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        let sequence = slideSequence()
        guard let index = Self.index(of: live.position, in: sequence) else { return reject(.liveSlideMissing) }
        let target = index + offset
        guard sequence.indices.contains(target) else { return reject(boundary) }
        return goLive(at: sequence[target])
    }

    /// Every slide in the playlist, in running order, following each presentation's active arrangement.
    /// Items with missing presentations are skipped.
    func slideSequence() -> [SlidePosition] {
        project.playlist.items.flatMap { item in
            (project.presentation(withID: item.presentationID)?.arrangedSlides ?? []).map {
                SlidePosition(itemID: item.id, slideID: $0.slideID, occurrence: $0.occurrence)
            }
        }
    }

    /// Where a position is in the sequence. If its exact repeat is gone (the arrangement changed), the slide's
    /// first appearance in the same item, so Next and Previous keep working.
    static func index(of position: SlidePosition, in sequence: [SlidePosition]) -> Int? {
        sequence.firstIndex(of: position)
            ?? sequence.firstIndex { $0.itemID == position.itemID && $0.slideID == position.slideID }
    }

    /// Drops a cue whose slide or repeat no longer exists, e.g. after a reflow or an arrangement change.
    func repairCue() {
        guard let preview = state.preview else { return }
        let stillPlays = project.presentation(forItem: preview.itemID)?.arrangedSlides
            .contains { $0.slideID == preview.slideID && $0.occurrence == preview.occurrence } ?? false
        if !stillPlays { state.preview = nil }
    }

    func editPresentation(_ presentationID: UUID, _ edit: (inout PresentationDocument) -> Void) -> CommandResult {
        // The props library is edited like any presentation, so the slide editor works on props.
        if presentationID == project.props.id {
            let before = project.props
            edit(&project.props)
            if project.props != before { project.props.updatedAt = now() }
            return applied()
        }
        guard let index = project.presentations.firstIndex(where: { $0.id == presentationID }) else {
            return reject(.unknownPresentation)
        }
        let before = project.presentations[index]
        edit(&project.presentations[index])
        // Views can write back an unchanged value (e.g. a text field on appear); that isn't an edit.
        if project.presentations[index] != before {
            project.presentations[index].updatedAt = now()
        }
        return applied()
    }

    func editSlide(
        _ slideID: UUID,
        inPresentation presentationID: UUID,
        _ edit: (inout SlideDocument) -> Void
    ) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
        return editPresentation(presentationID) { edit(&$0.slides[index]) }
    }

    func rejectMissingElement(slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard presentation.slide(withID: slideID) != nil else { return reject(.unknownSlide) }
        return reject(.unknownElement)
    }

    func editPrimaryText(
        slideID: UUID,
        inPresentation presentationID: UUID,
        _ edit: (inout TextElement) -> Void
    ) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
        return editPresentation(presentationID) { Self.editPrimaryText(of: &$0.slides[index], edit) }
    }

    /// Edits the slide's first text element, adding a body text element if it has none.
    static func editPrimaryText(of slide: inout SlideDocument, _ edit: (inout TextElement) -> Void) {
        if let textIndex = slide.elements.firstIndex(where: { if case .text = $0 { true } else { false } }),
           case .text(var element) = slide.elements[textIndex] {
            edit(&element)
            slide.elements[textIndex] = .text(element)
        } else {
            var element = TextElement(text: "")
            edit(&element)
            slide.elements.append(.text(element))
        }
    }

    func validate(_ background: SlideBackground?) -> CommandRejection? {
        if let assetID = background?.assetID, project.asset(withID: assetID) == nil { return .unknownMediaAsset }
        return nil
    }

    func applied() -> CommandResult {
        lastRejection = nil
        return .applied
    }

    func reject(_ rejection: CommandRejection) -> CommandResult {
        lastRejection = rejection
        Log.coordinator.debug("Rejected command: \(String(describing: rejection), privacy: .public)")
        return .rejected(rejection)
    }
}
