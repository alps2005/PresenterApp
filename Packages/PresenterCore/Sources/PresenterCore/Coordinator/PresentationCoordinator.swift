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

    @ObservationIgnored
    private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "PresentationCoordinator")

    public init(project: ProjectDocument) {
        self.project = project
        state.selectedItemID = project.playlist.items.first?.id
    }

    // MARK: - Derived state

    public var audienceScene: AudienceScene {
        if state.isBlackout { return .black }
        guard let live = state.live else { return .empty }
        return .slide(live.rendered)
    }

    /// The slide that `nextSlide()` would take live, following playlist order.
    public var upNextPosition: SlidePosition? {
        guard let live = state.live else { return nil }
        let sequence = slideSequence()
        guard let index = sequence.firstIndex(of: live.position), index + 1 < sequence.count else { return nil }
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
        state.isBlackout || (state.live == nil && state.cleared != nil)
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
    public func cueSlide(_ slideID: UUID, inItem itemID: UUID) -> CommandResult {
        let position = SlidePosition(itemID: itemID, slideID: slideID)
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
    public func takeLive(slideID: UUID, inItem itemID: UUID) -> CommandResult {
        let result = cueSlide(slideID, inItem: itemID)
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
    public func clearOutput() -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        state.cleared = live
        state.live = nil
        logger.info("Output cleared")
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
        guard changed else { return reject(.nothingToRestore) }
        logger.info("Output restored")
        return applied()
    }

    // MARK: - Editing commands
    // Edits change the project only. The live snapshot is untouched until the operator takes a slide live again.

    /// Creates a presentation with one blank slide, appends it to the playlist and selects it.
    @discardableResult
    public func addPresentation(title: String) -> PresentationItem {
        let presentation = PresentationDocument(title: title, slides: [.text("")])
        let item = PresentationItem(presentationID: presentation.id)
        project.presentations.append(presentation)
        project.playlist.items.append(item)
        state.selectedItemID = item.id
        state.preview = SlidePosition(itemID: item.id, slideID: presentation.slides[0].id)
        lastRejection = nil
        return item
    }

    @discardableResult
    public func renamePresentation(_ presentationID: UUID, to title: String) -> CommandResult {
        editPresentation(presentationID) { $0.title = title }
    }

    /// Inserts a blank slide after the cued slide (if it belongs to this item) or at the end, and cues it.
    @discardableResult
    public func addSlide(toItem itemID: UUID) -> CommandResult {
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

    /// Replaces the slide's text. A slide without a text element gets a body text element.
    @discardableResult
    public func updateSlideText(_ text: String, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.text = text }
    }

    // MARK: - Formatting commands

    @discardableResult
    public func setTextStyle(_ style: TextStyle, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.style = style }
    }

    /// Positions the slide's text. Nil returns it to the default centred layout.
    @discardableResult
    public func setTextBox(_ box: TextBox?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        editPrimaryText(slideID: slideID, inPresentation: presentationID) { $0.box = box }
    }

    /// Copies one slide's text style and position to every slide in its presentation. Text is untouched.
    @discardableResult
    public func applyTextFormatToAllSlides(from slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
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

    /// Sets a slide's own background. Nil makes it inherit its presentation's background again.
    @discardableResult
    public func setSlideBackground(_ background: SlideBackground?, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard let index = presentation.index(ofSlide: slideID) else { return reject(.unknownSlide) }
        if let rejection = validate(background) { return reject(rejection) }
        return editPresentation(presentationID) { $0.slides[index].background = background }
    }

    /// Sets the background for every slide of a presentation that doesn't set its own. Nil uses the default.
    @discardableResult
    public func setPresentationBackground(_ background: SlideBackground?, presentationID: UUID) -> CommandResult {
        guard project.presentation(withID: presentationID) != nil else { return reject(.unknownPresentation) }
        if let rejection = validate(background) { return reject(rejection) }
        return editPresentation(presentationID) { $0.background = background }
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

    @discardableResult
    public func deleteSlide(_ slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
        guard presentation.index(ofSlide: slideID) != nil else { return reject(.unknownSlide) }
        let result = editPresentation(presentationID) { $0.slides.removeAll { $0.id == slideID } }
        if state.preview?.slideID == slideID { state.preview = nil }
        return result
    }

    /// Removes an entry from the playlist. The presentation stays in the library.
    @discardableResult
    public func removeItem(_ itemID: UUID) -> CommandResult {
        guard let index = project.playlist.index(ofItem: itemID) else { return reject(.unknownItem) }
        project.playlist.items.remove(at: index)
        if state.preview?.itemID == itemID { state.preview = nil }
        if state.selectedItemID == itemID {
            let items = project.playlist.items
            state.selectedItemID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
        }
        return applied()
    }

    /// Moves playlist items, with the same semantics as SwiftUI's `onMove`.
    @discardableResult
    public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) -> CommandResult {
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

    // MARK: - Private

    private func goLive(at position: SlidePosition) -> CommandResult {
        guard let rendered = project.renderedSlide(at: position) else { return reject(.unknownSlide) }
        state.live = LiveSlide(position: position, rendered: rendered)
        state.cleared = nil
        logger.info("Live: item \(position.itemID, privacy: .public) slide \(position.slideID, privacy: .public)")
        return applied()
    }

    private func step(by offset: Int, boundary: CommandRejection) -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        let sequence = slideSequence()
        guard let index = sequence.firstIndex(of: live.position) else { return reject(.liveSlideMissing) }
        let target = index + offset
        guard sequence.indices.contains(target) else { return reject(boundary) }
        return goLive(at: sequence[target])
    }

    /// Every slide in the playlist, in running order. Items with missing presentations are skipped.
    private func slideSequence() -> [SlidePosition] {
        project.playlist.items.flatMap { item in
            (project.presentation(withID: item.presentationID)?.slides ?? []).map {
                SlidePosition(itemID: item.id, slideID: $0.id)
            }
        }
    }

    private func editPresentation(_ presentationID: UUID, _ edit: (inout PresentationDocument) -> Void) -> CommandResult {
        guard let index = project.presentations.firstIndex(where: { $0.id == presentationID }) else {
            return reject(.unknownPresentation)
        }
        edit(&project.presentations[index])
        project.presentations[index].updatedAt = .now
        return applied()
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
