import Foundation

// Presentations, the playlist, songs, reflow and arrangements. Undoable edits.
extension PresentationCoordinator {
    // MARK: - Editing commands
    // Edits change the project only. The live snapshot is untouched until the operator takes a slide live again.

    /// Creates a presentation with one blank slide, appends it to the playlist and selects it.
    @discardableResult
    public func addPresentation(title: String) -> PresentationItem {
        recordingUndo("Add Presentation") {
            let presentation = PresentationDocument(title: title, slides: [.text("")], themeID: defaultThemeID)
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
    /// The song follows `themeID` (the New Song sheet starts with `defaultThemeID`); nil, or a deleted theme, none.
    public func addSong(title: String, lyrics: String, maxLinesPerSlide: Int? = nil, themeID: UUID? = nil) -> PresentationItem? {
        let slides = LyricsParser.slides(from: lyrics, maxLinesPerSlide: maxLinesPerSlide)
        guard !slides.isEmpty else { return nil }
        return recordingUndo("Add Song") {
            let presentation = PresentationDocument(title: title.isEmpty ? "Untitled Song" : title, slides: slides,
                                                    themeID: existingThemeID(themeID))
            let item = PresentationItem(presentationID: presentation.id)
            project.presentations.append(presentation)
            project.playlist.items.append(item)
            state.selectedItemID = item.id
            lastRejection = nil
            Log.coordinator.info("Added song \(presentation.id, privacy: .public) with \(slides.count) slides")
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
        let element = TextElement(text: text, role: look?.role ?? .body, style: look?.style, box: look?.box,
                                  overrides: look?.overrides ?? [])
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
        guard presentationID != project.props.id, project.presentation(withID: presentationID) != nil else {
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
            guard presentationID != project.props.id, project.presentation(withID: presentationID) != nil else {
                return reject(.unknownPresentation)
            }
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
}
