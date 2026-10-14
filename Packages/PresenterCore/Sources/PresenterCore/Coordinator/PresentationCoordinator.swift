import Foundation
import Observation
import os

/// Owns the project and all live state. Views and output windows observe it and send commands;
/// nothing else mutates presentation state.
@MainActor
@Observable
public final class PresentationCoordinator {
    public private(set) var project: ProjectDocument
    public private(set) var state = PresentationState()
    /// The most recent rejected command, for surfacing to the operator. Cleared by the next applied command.
    public private(set) var lastRejection: CommandRejection?

    /// Project snapshots taken before each edit, newest last. Live commands are never recorded.
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    /// Consecutive edits with the same key within `coalescingInterval` (typing, dragging a slider) undo together.
    @ObservationIgnored private var coalescingKey: String?
    @ObservationIgnored private var lastEditTime = Date.distantPast
    @ObservationIgnored private var recordingDepth = 0
    /// The clock used for coalescing. Tests replace it.
    @ObservationIgnored var now: () -> Date = { Date() }

    static let undoLimit = 100
    static let coalescingInterval: TimeInterval = 1

    private struct UndoEntry {
        let project: ProjectDocument
        let actionName: String
    }

    @ObservationIgnored
    private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "PresentationCoordinator")

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
    }

    /// True when the live slide (or the background it inherits) has been edited since it was taken live,
    /// so the audience sees an older version.
    public var liveSlideHasPendingEdits: Bool {
        guard let live = state.live, let current = project.renderedSlide(at: live.position) else { return false }
        return current != live.rendered
    }

    // MARK: - Live commands

    @discardableResult
    public func selectItem(_ itemID: UUID) -> CommandResult {
        guard project.playlist.item(withID: itemID) != nil else { return reject(.unknownItem) }
        state.selectedItemID = itemID
        return applied()
    }

    /// Cues a slide for preview. Never changes the audience output.
    @discardableResult
    public func cueSlide(_ slideID: UUID, inItem itemID: UUID, occurrence: Int = 0) -> CommandResult {
        let position = SlidePosition(itemID: itemID, slideID: slideID, occurrence: occurrence)
        guard project.playlist.item(withID: itemID) != nil else { return reject(.unknownItem) }
        guard project.slide(at: position) != nil else { return reject(.unknownSlide) }
        state.selectedItemID = itemID
        state.preview = position
        return applied()
    }

    /// Sends the cued slide to the audience output. Blackout, if active, stays active.
    @discardableResult
    public func takeLive() -> CommandResult {
        guard let preview = state.preview else { return reject(.nothingCued) }
        return goLive(at: preview)
    }

    /// Cues and takes a slide live in one step (e.g. double-click).
    @discardableResult
    public func takeLive(slideID: UUID, inItem itemID: UUID, occurrence: Int = 0) -> CommandResult {
        let result = cueSlide(slideID, inItem: itemID, occurrence: occurrence)
        guard result.isApplied else { return result }
        return takeLive()
    }

    @discardableResult
    public func nextSlide() -> CommandResult {
        step(by: 1, boundary: .atEndOfPlaylist)
    }

    @discardableResult
    public func previousSlide() -> CommandResult {
        step(by: -1, boundary: .atStartOfPlaylist)
    }

    /// Removes the live slide from the audience output, leaving the empty background.
    @discardableResult
    /// Clear Slide: removes the live slide's words and elements. The background layer stays, as in ProPresenter.
    public func clearOutput() -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        state.cleared = live
        state.live = nil
        logger.info("Slide cleared")
        return applied()
    }

    /// Clear Background: removes the background layer, back to the app's default. The live slide stays.
    @discardableResult
    public func clearBackground() -> CommandResult {
        guard let background = state.liveBackground else { return reject(.nothingToClear) }
        state.clearedBackground = background
        state.liveBackground = nil
        logger.info("Background cleared")
        return applied()
    }

    /// Clear All: removes the slide and the background.
    @discardableResult
    public func clearAll() -> CommandResult {
        guard state.live != nil || state.liveBackground != nil else { return reject(.nothingLive) }
        if state.live != nil { _ = clearOutput() }
        if state.liveBackground != nil { _ = clearBackground() }
        return applied()
    }

    @discardableResult
    public func blackout() -> CommandResult {
        state.isBlackout = true
        logger.info("Blackout on")
        return applied()
    }

    /// Lifts blackout and brings back a cleared slide, if any.
    @discardableResult
    public func restoreOutput() -> CommandResult {
        var changed = false
        if state.isBlackout {
            state.isBlackout = false
            changed = true
        }
        if state.live == nil, let cleared = state.cleared {
            state.live = cleared
            state.cleared = nil
            changed = true
        }
        if state.liveBackground == nil, let background = state.clearedBackground {
            state.liveBackground = background
            state.clearedBackground = nil
            changed = true
        }
        guard changed else { return reject(.nothingToRestore) }
        logger.info("Output restored")
        return applied()
    }

    // MARK: - Undo

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// What Undo would revert, e.g. "Typing", for the Edit menu.
    public var undoActionName: String? { undoStack.last?.actionName }
    public var redoActionName: String? { redoStack.last?.actionName }

    /// Restores the project to before the last edit. The audience output never changes: the live slide is a
    /// snapshot, and only editing commands are recorded.
    public func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(UndoEntry(project: project, actionName: entry.actionName))
        restore(entry.project)
        logger.info("Undo \(entry.actionName, privacy: .public)")
    }

    public func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(UndoEntry(project: project, actionName: entry.actionName))
        restore(entry.project)
        logger.info("Redo \(entry.actionName, privacy: .public)")
    }

    private func restore(_ snapshot: ProjectDocument) {
        project = snapshot
        coalescingKey = nil
        // Keep selection and cue pointing at things that still exist; live state is left alone.
        if let selected = state.selectedItemID, project.playlist.item(withID: selected) == nil {
            state.selectedItemID = project.playlist.items.first?.id
        }
        if let preview = state.preview, project.slide(at: preview) == nil {
            state.preview = nil
        }
        lastRejection = nil
    }

    /// Runs an editing command and, if it changed the project, records the previous project for Undo.
    private func recordingUndo<Result>(_ actionName: String, coalescing key: String? = nil, _ body: () -> Result) -> Result {
        // Commands that call other commands record once, for the outermost one.
        guard recordingDepth == 0 else { return body() }
        recordingDepth += 1
        defer { recordingDepth -= 1 }
        let before = project
        let result = body()
        guard project != before else { return result }
        let time = now()
        redoStack.removeAll()
        if let key, key == coalescingKey, time.timeIntervalSince(lastEditTime) < Self.coalescingInterval, !undoStack.isEmpty {
            lastEditTime = time
            return result
        }
        undoStack.append(UndoEntry(project: before, actionName: actionName))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        coalescingKey = key
        lastEditTime = time
        return result
    }

    // MARK: - Project commands

    /// Swaps in a different project, e.g. one opened from disk. The audience output is left alone:
    /// the live snapshot, cleared slide and blackout carry over until the operator takes something live.
    /// Selection and cue move to the new project's first item.
    public func replaceProject(_ newProject: ProjectDocument) {
        project = newProject
        // Undo can't reach back into a different project.
        undoStack.removeAll()
        redoStack.removeAll()
        coalescingKey = nil
        state.selectedItemID = newProject.playlist.items.first?.id
        state.preview = nil
        lastRejection = nil
        logger.info("Opened project \(newProject.id, privacy: .public)")
    }

    // MARK: - Editing commands
    // Edits change the project only. The live snapshot is untouched until the operator takes a slide live again.

    /// Creates a presentation with one blank slide, appends it to the playlist and selects it.
    @discardableResult
    public func addPresentation(title: String) -> PresentationItem {
        recordingUndo("Add Presentation") {
            let presentation = PresentationDocument(title: title, slides: [.text("")])
            let item = PresentationItem(presentationID: presentation.id)
            project.presentations.append(presentation)
            project.playlist.items.append(item)
            state.selectedItemID = item.id
            state.preview = SlidePosition(itemID: item.id, slideID: presentation.slides[0].id)
            lastRejection = nil
            return item
        }
    }

    /// Creates a presentation from pasted lyrics (see `LyricsParser`), adds it to the playlist and selects it.
    /// Returns nil, changing nothing, when the lyrics contain no words.
    @discardableResult
    public func addSong(title: String, lyrics: String, maxLinesPerSlide: Int? = nil) -> PresentationItem? {
        let slides = LyricsParser.slides(from: lyrics, maxLinesPerSlide: maxLinesPerSlide)
        guard !slides.isEmpty else { return nil }
        return recordingUndo("Add Song") {
            let presentation = PresentationDocument(title: title.isEmpty ? "Untitled Song" : title, slides: slides)
            let item = PresentationItem(presentationID: presentation.id)
            project.presentations.append(presentation)
            project.playlist.items.append(item)
            state.selectedItemID = item.id
            lastRejection = nil
            logger.info("Added song \(presentation.id, privacy: .public) with \(slides.count) slides")
            return item
        }
    }

    // MARK: - Reflow and arrangements

    /// Rewrites a presentation's words from Reflow text (New Song format). Slides are matched by position, so each
    /// keeps its identity, look, background and transition; new slides copy the look of the slide before them,
    /// and slides past the end of the text are removed.
    @discardableResult
    public func reflow(_ text: String, presentationID: UUID) -> CommandResult {
        recordingUndo("Reflow", coalescing: "reflow-\(presentationID)") {
            let parsed = LyricsParser.slides(from: text)
            let result = editPresentation(presentationID) { presentation in
                var slides: [SlideDocument] = []
                for (index, new) in parsed.enumerated() {
                    if index < presentation.slides.count {
                        var slide = presentation.slides[index]
                        Self.editPrimaryText(of: &slide) { $0.text = new.primaryText }
                        slide.label = new.label
                        slides.append(slide)
                    } else {
                        slides.append(Self.slide(text: new.primaryText, label: new.label, lookingLike: slides.last))
                    }
                }
                presentation.slides = slides
            }
            repairCue()
            return result
        }
    }

    /// A new slide with `text` that copies `template`'s text style, position, background and transition.
    private static func slide(text: String, label: String?, lookingLike template: SlideDocument?) -> SlideDocument {
        guard let template else {
            var slide = SlideDocument.text(text)
            slide.label = label
            return slide
        }
        let look = template.primaryTextElement
        let element = TextElement(text: text, role: look?.role ?? .body, style: look?.style, box: look?.box)
        return SlideDocument(elements: [.text(element)], background: template.background,
                             transition: template.transition, label: label)
    }

    /// Adds an arrangement and makes it the one that plays.
    @discardableResult
    public func addArrangement(name: String, groups: [String], toPresentation presentationID: UUID) -> Arrangement? {
        recordingUndo("Add Arrangement") {
            let arrangement = Arrangement(name: name.isEmpty ? "Arrangement" : name, groups: groups)
            let result = editPresentation(presentationID) { presentation in
                presentation.arrangements.append(arrangement)
                presentation.activeArrangementID = arrangement.id
            }
            repairCue()
            return result.isApplied ? arrangement : nil
        }
    }

    @discardableResult
    public func updateArrangement(_ arrangement: Arrangement, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Edit Arrangement") {
            guard project.presentation(withID: presentationID)?.arrangements.contains(where: { $0.id == arrangement.id }) == true else {
                return reject(.unknownArrangement)
            }
            let result = editPresentation(presentationID) { presentation in
                if let index = presentation.arrangements.firstIndex(where: { $0.id == arrangement.id }) {
                    presentation.arrangements[index] = arrangement
                }
            }
            repairCue()
            return result
        }
    }

    @discardableResult
    public func deleteArrangement(_ arrangementID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Delete Arrangement") {
            guard project.presentation(withID: presentationID)?.arrangements.contains(where: { $0.id == arrangementID }) == true else {
                return reject(.unknownArrangement)
            }
            let result = editPresentation(presentationID) { presentation in
                presentation.arrangements.removeAll { $0.id == arrangementID }
                if presentation.activeArrangementID == arrangementID { presentation.activeArrangementID = nil }
            }
            repairCue()
            return result
        }
    }

    /// Chooses the arrangement that plays. Nil plays every slide in order.
    @discardableResult
    public func setActiveArrangement(_ arrangementID: UUID?, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Arrangement") {
            if let arrangementID,
               project.presentation(withID: presentationID)?.arrangements.contains(where: { $0.id == arrangementID }) != true {
                return reject(.unknownArrangement)
            }
            let result = editPresentation(presentationID) { $0.activeArrangementID = arrangementID }
            repairCue()
            return result
        }
    }

    // MARK: - Library

    /// Adds a library presentation to the end of the playlist and selects it.
    @discardableResult
    public func addToPlaylist(_ presentationID: UUID) -> PresentationItem? {
        guard project.presentation(withID: presentationID) != nil else {
            _ = reject(.unknownPresentation)
            return nil
        }
        return recordingUndo("Add to Playlist") {
            let item = PresentationItem(presentationID: presentationID)
            project.playlist.items.append(item)
            state.selectedItemID = item.id
            lastRejection = nil
            return item
        }
    }

    /// Deletes a presentation from the library and removes it from the playlist. If it's live, it stays on the
    /// audience output until something else is taken live.
    @discardableResult
    public func deletePresentation(_ presentationID: UUID) -> CommandResult {
        recordingUndo("Delete Presentation") {
            guard project.presentation(withID: presentationID) != nil else { return reject(.unknownPresentation) }
            project.presentations.removeAll { $0.id == presentationID }
            project.playlist.items.removeAll { $0.presentationID == presentationID }
            if let selected = state.selectedItemID, project.playlist.item(withID: selected) == nil {
                state.selectedItemID = project.playlist.items.first?.id
            }
            if let preview = state.preview, project.slide(at: preview) == nil { state.preview = nil }
            return applied()
        }
    }

    /// Sets a slide's group label ("Verse 1", "Chorus"…). Empty text removes it.
    @discardableResult
    public func setLabel(_ label: String, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Group Label", coalescing: "label-\(slideID)") {
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            return editSlide(slideID, inPresentation: presentationID) { $0.label = trimmed.isEmpty ? nil : trimmed }
        }
    }

    @discardableResult
    public func renamePresentation(_ presentationID: UUID, to title: String) -> CommandResult {
        recordingUndo("Rename", coalescing: "rename-\(presentationID)") {
            editPresentation(presentationID) { $0.title = title }
        }
    }

    /// Inserts a blank slide after the cued slide (if it belongs to this item) or at the end, and cues it.
    @discardableResult
    public func addSlide(toItem itemID: UUID) -> CommandResult {
        recordingUndo("Add Slide") {
            guard let item = project.playlist.item(withID: itemID) else { return reject(.unknownItem) }
            let slide = SlideDocument.text("")
            let result = editPresentation(item.presentationID) { presentation in
                if let preview = state.preview, preview.itemID == itemID,
                   let index = presentation.index(ofSlide: preview.slideID) {
                    presentation.slides.insert(slide, at: index + 1)
                } else {
                    presentation.slides.append(slide)
                }
            }
            guard result.isApplied else { return result }
            state.selectedItemID = itemID
            state.preview = SlidePosition(itemID: itemID, slideID: slide.id)
            return result
        }
    }

    /// Inserts a blank slide after `slideID` (or at the end when nil or unknown) and returns it.
    /// Unlike `addSlide(toItem:)`, the cue is left alone: the slide editor selects slides without cueing them.
    @discardableResult
    public func insertSlide(after slideID: UUID?, inPresentation presentationID: UUID) -> SlideDocument? {
        recordingUndo("Add Slide") {
            let slide = SlideDocument.text("")
            let result = editPresentation(presentationID) { presentation in
                if let slideID, let index = presentation.index(ofSlide: slideID) {
                    presentation.slides.insert(slide, at: index + 1)
                } else {
                    presentation.slides.append(slide)
                }
            }
            return result.isApplied ? slide : nil
        }
    }

    /// Replaces the slide's text. A slide without a text element gets a body text element.
    @discardableResult
    public func updateSlideText(_ text: String, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Typing", coalescing: "text-\(slideID)") {
            editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.text = text }
        }
    }

    // MARK: - Formatting commands

    @discardableResult
    public func setTextStyle(_ style: TextStyle, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Text Style", coalescing: "style-\(slideID)") {
            editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.style = style }
        }
    }

    /// Positions the slide's text. Nil returns it to the default centred layout.
    @discardableResult
    public func setTextBox(_ box: TextBox?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Text Position", coalescing: "box-\(slideID)") {
            editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.box = box }
        }
    }

    /// Copies one slide's text style and position to every slide in its presentation. Text is untouched.
    @discardableResult
    public func applyTextFormatToAllSlides(from slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Apply to All Slides") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard let source = presentation.slide(withID: slideID) else { return reject(.unknownSlide) }
            let format = source.primaryTextElement ?? TextElement(text: "")
            logger.info("Applied text format to all slides of \(presentationID, privacy: .public)")
            return editPresentation(presentationID) { presentation in
                for index in presentation.slides.indices {
                    Self.editPrimaryText(of: &presentation.slides[index]) { element in
                        element.style = format.style
                        element.box = format.box
                    }
                }
            }
        }
    }

    /// Sets a slide's own background. Nil makes it inherit its presentation's background again.
    @discardableResult
    public func setSlideBackground(_ background: SlideBackground?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Background", coalescing: "background-\(slideID)") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
            if let rejection = validate(background) { return reject(rejection) }
            return editPresentation(presentationID) { $0.slides[index].background = background }
        }
    }

    /// Sets the background for every slide of a presentation that doesn't set its own. Nil uses the default.
    @discardableResult
    public func setPresentationBackground(_ background: SlideBackground?, presentationID: UUID) -> CommandResult {
        recordingUndo("Background", coalescing: "background-\(presentationID)") {
            guard project.presentation(withID: presentationID) != nil else { return reject(.unknownPresentation) }
            if let rejection = validate(background) { return reject(rejection) }
            return editPresentation(presentationID) { $0.background = background }
        }
    }

    /// Records an imported media file so backgrounds can reference it. Adding the same asset twice is a no-op.
    @discardableResult
    public func addMediaAsset(_ asset: MediaAsset) -> CommandResult {
        if project.asset(withID: asset.id) == nil {
            project.mediaAssets.append(asset)
            logger.info("Added media asset \(asset.id, privacy: .public)")
        }
        return applied()
    }

    // MARK: - Element commands
    // Text boxes, shapes and images placed on a slide. Later elements draw on top of earlier ones.

    /// Adds an element on top of the slide's other elements.
    @discardableResult
    public func addElement(_ element: SlideElement, toSlide slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Add") {
            if let assetID = element.assetID, project.asset(withID: assetID) == nil { return reject(.unknownMediaAsset) }
            return editSlide(slideID, inPresentation: presentationID) { $0.elements.append(element) }
        }
    }

    /// Replaces the element with the same ID.
    @discardableResult
    public func updateElement(_ element: SlideElement, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Change", coalescing: "element-\(element.id)") {
            if let assetID = element.assetID, project.asset(withID: assetID) == nil { return reject(.unknownMediaAsset) }
            guard project.presentation(withID: presentationID)?.slide(withID: slideID)?.element(withID: element.id) != nil else {
                return rejectMissingElement(slideID: slideID, inPresentation: presentationID)
            }
            return editSlide(slideID, inPresentation: presentationID) { slide in
                if let index = slide.elements.firstIndex(where: { $0.id == element.id }) { slide.elements[index] = element }
            }
        }
    }

    @discardableResult
    public func deleteElement(_ elementID: UUID, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Delete") {
            guard project.presentation(withID: presentationID)?.slide(withID: slideID)?.element(withID: elementID) != nil else {
                return rejectMissingElement(slideID: slideID, inPresentation: presentationID)
            }
            return editSlide(slideID, inPresentation: presentationID) { $0.elements.removeAll { $0.id == elementID } }
        }
    }

    /// The offset for a duplicate or a paste onto the same spot: 20 points on the 1920×1080 canvas.
    public static let duplicateOffset = (dx: 20.0 / 1920, dy: 20.0 / 1080)

    /// Copies an element, slightly offset, directly above the original, and returns the copy.
    @discardableResult
    public func duplicateElement(_ elementID: UUID, slideID: UUID, inPresentation presentationID: UUID) -> SlideElement? {
        recordingUndo("Duplicate") {
            guard let slide = project.presentation(withID: presentationID)?.slide(withID: slideID),
                  let index = slide.elements.firstIndex(where: { $0.id == elementID }) else {
                _ = rejectMissingElement(slideID: slideID, inPresentation: presentationID)
                return nil
            }
            let copy = slide.elements[index].duplicated(offsetBy: Self.duplicateOffset.dx, Self.duplicateOffset.dy)
            let result = editSlide(slideID, inPresentation: presentationID) { $0.elements.insert(copy, at: index + 1) }
            return result.isApplied ? copy : nil
        }
    }

    public enum ElementOrder: Sendable {
        case forward, backward, front, back
    }

    /// Moves an element up or down the drawing order. Already at the top or bottom is a no-op.
    @discardableResult
    public func reorderElement(
        _ elementID: UUID,
        _ order: ElementOrder,
        slideID: UUID,
        inPresentation presentationID: UUID
    ) -> CommandResult {
        recordingUndo("Arrange") {
            guard project.presentation(withID: presentationID)?.slide(withID: slideID)?.element(withID: elementID) != nil else {
                return rejectMissingElement(slideID: slideID, inPresentation: presentationID)
            }
            return editSlide(slideID, inPresentation: presentationID) { slide in
                guard let index = slide.elements.firstIndex(where: { $0.id == elementID }) else { return }
                let last = slide.elements.count - 1
                let target = switch order {
                case .forward: min(index + 1, last)
                case .backward: max(index - 1, 0)
                case .front: last
                case .back: 0
                }
                guard target != index else { return }
                let element = slide.elements.remove(at: index)
                slide.elements.insert(element, at: target)
            }
        }
    }

    // MARK: - Slide order and transitions

    /// Moves slides within a presentation, with the same semantics as SwiftUI's `onMove`.
    @discardableResult
    public func moveSlides(inPresentation presentationID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) -> CommandResult {
        recordingUndo("Reorder Slides") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard source.allSatisfy(presentation.slides.indices.contains), (0...presentation.slides.count).contains(destination) else {
                return reject(.unknownSlide)
            }
            return editPresentation(presentationID) { presentation in
                let moving = source.map { presentation.slides[$0] }
                let insertion = destination - source.count(in: 0..<destination)
                for index in source.reversed() { presentation.slides.remove(at: index) }
                presentation.slides.insert(contentsOf: moving, at: insertion)
            }
        }
    }

    /// Sets how the audience output changes to this slide. Nil cuts instantly.
    @discardableResult
    public func setTransition(_ transition: SlideTransition?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Transition", coalescing: "transition-\(slideID)") {
            editSlide(slideID, inPresentation: presentationID) { $0.transition = transition }
        }
    }

    /// Copies one slide's transition to every slide in its presentation.
    @discardableResult
    public func applyTransitionToAllSlides(from slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Apply to All Slides") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard let source = presentation.slide(withID: slideID) else { return reject(.unknownSlide) }
            return editPresentation(presentationID) { presentation in
                for index in presentation.slides.indices { presentation.slides[index].transition = source.transition }
            }
        }
    }

    /// Sets a slide's presenter notes. Empty text clears them.
    @discardableResult
    public func setNotes(_ notes: String, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Notes", coalescing: "notes-\(slideID)") {
            editSlide(slideID, inPresentation: presentationID) { $0.notes = notes.isEmpty ? nil : notes }
        }
    }

    @discardableResult
    public func deleteSlide(_ slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Delete Slide") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard presentation.index(ofSlide: slideID) != nil else { return reject(.unknownSlide) }
            let result = editPresentation(presentationID) { $0.slides.removeAll { $0.id == slideID } }
            if state.preview?.slideID == slideID { state.preview = nil }
            return result
        }
    }

    /// Removes an entry from the playlist. The presentation stays in the library.
    @discardableResult
    public func removeItem(_ itemID: UUID) -> CommandResult {
        recordingUndo("Remove from Playlist") {
            guard let index = project.playlist.index(ofItem: itemID) else { return reject(.unknownItem) }
            project.playlist.items.remove(at: index)
            if state.preview?.itemID == itemID { state.preview = nil }
            if state.selectedItemID == itemID {
                let items = project.playlist.items
                state.selectedItemID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
            }
            return applied()
        }
    }

    /// Moves playlist items, with the same semantics as SwiftUI's `onMove`.
    @discardableResult
    public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) -> CommandResult {
        recordingUndo("Reorder Playlist") {
            var items = project.playlist.items
            guard source.allSatisfy(items.indices.contains), (0...items.count).contains(destination) else {
                return reject(.unknownItem)
            }
            let moving = source.map { items[$0] }
            let insertion = destination - source.count(in: 0..<destination)
            for index in source.reversed() { items.remove(at: index) }
            items.insert(contentsOf: moving, at: insertion)
            project.playlist.items = items
            return applied()
        }
    }

    // MARK: - Private

    private func goLive(at position: SlidePosition) -> CommandResult {
        guard let rendered = project.renderedSlide(at: position) else { return reject(.unknownSlide) }
        state.live = LiveSlide(position: position, rendered: rendered)
        state.cleared = nil
        // An opaque slide replaces the background layer; a transparent one leaves what's on screen.
        if rendered.background != .transparent {
            state.liveBackground = rendered.background
            state.clearedBackground = nil
        }
        logger.info("Live: item \(position.itemID, privacy: .public) slide \(position.slideID, privacy: .public)")
        return applied()
    }

    private func step(by offset: Int, boundary: CommandRejection) -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        let sequence = slideSequence()
        guard let index = Self.index(of: live.position, in: sequence) else { return reject(.liveSlideMissing) }
        let target = index + offset
        guard sequence.indices.contains(target) else { return reject(boundary) }
        return goLive(at: sequence[target])
    }

    /// Every slide in the playlist, in running order, following each presentation's active arrangement.
    /// Items with missing presentations are skipped.
    private func slideSequence() -> [SlidePosition] {
        project.playlist.items.flatMap { item in
            (project.presentation(withID: item.presentationID)?.arrangedSlides ?? []).map {
                SlidePosition(itemID: item.id, slideID: $0.slideID, occurrence: $0.occurrence)
            }
        }
    }

    /// Where a position is in the sequence. If its exact repeat is gone (the arrangement changed), the slide's
    /// first appearance in the same item, so Next and Previous keep working.
    private static func index(of position: SlidePosition, in sequence: [SlidePosition]) -> Int? {
        sequence.firstIndex(of: position)
            ?? sequence.firstIndex { $0.itemID == position.itemID && $0.slideID == position.slideID }
    }

    /// Drops a cue whose slide or repeat no longer exists, e.g. after a reflow or an arrangement change.
    private func repairCue() {
        guard let preview = state.preview else { return }
        let stillPlays = project.presentation(forItem: preview.itemID)?.arrangedSlides
            .contains { $0.slideID == preview.slideID && $0.occurrence == preview.occurrence } ?? false
        if !stillPlays { state.preview = nil }
    }

    private func editPresentation(_ presentationID: UUID, _ edit: (inout PresentationDocument) -> Void) -> CommandResult {
        guard let index = project.presentations.firstIndex(where: { $0.id == presentationID }) else {
            return reject(.unknownPresentation)
        }
        let before = project.presentations[index]
        edit(&project.presentations[index])
        // Views can write back an unchanged value (e.g. a text field on appear); that isn't an edit.
        if project.presentations[index] != before {
            project.presentations[index].updatedAt = .now
        }
        return applied()
    }

    private func editSlide(
        _ slideID: UUID,
        inPresentation presentationID: UUID,
        _ edit: (inout SlideDocument) -> Void
    ) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
        return editPresentation(presentationID) { edit(&$0.slides[index]) }
    }

    private func rejectMissingElement(slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard presentation.slide(withID: slideID) != nil else { return reject(.unknownSlide) }
        return reject(.unknownElement)
    }

    private func editPrimaryText(
        slideID: UUID,
        inPresentation presentationID: UUID,
        _ edit: (inout TextElement) -> Void
    ) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
        return editPresentation(presentationID) { Self.editPrimaryText(of: &$0.slides[index], edit) }
    }

    /// Edits the slide's first text element, adding a body text element if it has none.
    private static func editPrimaryText(of slide: inout SlideDocument, _ edit: (inout TextElement) -> Void) {
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

    private func validate(_ background: SlideBackground?) -> CommandRejection? {
        if let assetID = background?.assetID, project.asset(withID: assetID) == nil { return .unknownMediaAsset }
        return nil
    }

    private func applied() -> CommandResult {
        lastRejection = nil
        return .applied
    }

    private func reject(_ rejection: CommandRejection) -> CommandResult {
        lastRejection = rejection
        logger.debug("Rejected command: \(String(describing: rejection), privacy: .public)")
        return .rejected(rejection)
    }
}
