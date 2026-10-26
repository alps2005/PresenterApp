import Foundation

// Scripture: a Bible passage becomes an ordinary presentation of text slides (see `ScriptureSlides`).
extension PresentationCoordinator {
    /// The theme to suggest for a passage: one named Scripture (or Escrituras), else the project's default.
    public var suggestedScriptureThemeID: UUID? {
        let names: Set<String> = ["scripture", "escritura", "escrituras", "biblia", "bible"]
        return project.themes.first { names.contains($0.name.lowercased()) }?.id ?? project.defaultThemeID
    }

    /// Adds the passage as a new presentation in the library and at the end of the show, and selects it. With a
    /// `second` passage (the same reference in another Bible), each slide shows both. Its slides follow `themeID`
    /// (nil, or a deleted theme, none). Returns nil, changing nothing, when the passage has no verses.
    @discardableResult
    public func addScripture(_ passage: BiblePassage, second: BiblePassage? = nil,
                             options: ScriptureSlides.Options = ScriptureSlides.Options(), themeID: UUID?) -> PresentationItem? {
        let slides = ScriptureSlides.make(passage, second: second, options: options)
        guard !slides.isEmpty else { return nil }
        let title = second.map { "\(passage.caption) / \($0.translationAbbreviation)" } ?? passage.caption
        return recordingUndo("Add Scripture") {
            let presentation = PresentationDocument(title: title, slides: slides, themeID: existingThemeID(themeID),
                                                    kind: .scripture)
            let item = PresentationItem(presentationID: presentation.id)
            project.presentations.append(presentation)
            project.playlist.items.append(item)
            state.selectedItemID = item.id
            lastRejection = nil
            Log.coordinator.info("Added scripture \(presentation.id, privacy: .public) with \(slides.count) slides")
            return item
        }
    }
}
