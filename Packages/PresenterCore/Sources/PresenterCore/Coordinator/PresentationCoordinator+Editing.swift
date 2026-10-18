import Foundation

// Slide editing: formatting, backgrounds, elements, slide order and transitions. Undoable edits.
extension PresentationCoordinator {
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
            // As drawn: text that follows a theme may have an out-of-date style stored.
            let stored = source.primaryTextElement ?? TextElement(text: "")
            let format = project.theme(for: presentation)?.applied(to: stored) ?? stored
            Log.coordinator.info("Applied text format to all slides of \(presentationID, privacy: .public)")
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
    /// Not an undoable edit: the asset is added to every undo and redo snapshot too, so undoing an earlier edit
    /// never loses an import (its file is already in the media folder). Deleting it is undoable.
    @discardableResult
    public func addMediaAsset(_ asset: MediaAsset) -> CommandResult {
        if project.asset(withID: asset.id) == nil {
            project.mediaAssets.append(asset)
            for index in undoStack.indices where undoStack[index].project.asset(withID: asset.id) == nil {
                undoStack[index].project.mediaAssets.append(asset)
            }
            for index in redoStack.indices where redoStack[index].project.asset(withID: asset.id) == nil {
                redoStack[index].project.mediaAssets.append(asset)
            }
            Log.coordinator.info("Added media asset \(asset.id, privacy: .public)")
        }
        return applied()
    }

    /// Removes a media file from the project, and from every background and image that uses it (those fall back
    /// to the next background, or lose the image). Undoable. The audience output is left alone, and the file stays
    /// in the media folder until a relaunch, so Undo can bring it back.
    @discardableResult
    public func removeMediaAsset(_ assetID: UUID) -> CommandResult {
        recordingUndo("Delete Media") {
            guard project.asset(withID: assetID) != nil else { return reject(.unknownMediaAsset) }
            let date = now()
            for index in project.presentations.indices where project.presentations[index].uses(assetID) {
                project.presentations[index].removeMedia(assetID)
                project.presentations[index].updatedAt = date
            }
            if project.props.uses(assetID) { project.props.removeMedia(assetID) }
            for index in project.themes.indices where project.themes[index].background?.assetID == assetID {
                project.themes[index].background = nil
            }
            project.mediaAssets.removeAll { $0.id == assetID }
            Log.coordinator.info("Deleted media asset \(assetID, privacy: .public)")
            return applied()
        }
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
}
