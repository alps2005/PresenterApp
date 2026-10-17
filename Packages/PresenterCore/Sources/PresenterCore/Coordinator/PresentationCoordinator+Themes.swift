import Foundation

// Themes: reusable looks that presentations follow. Undoable edits.
extension PresentationCoordinator {
    /// The theme new presentations and songs start with, if it still exists.
    var defaultThemeID: UUID? {
        existingThemeID(project.defaultThemeID)
    }

    func existingThemeID(_ themeID: UUID?) -> UUID? {
        themeID.flatMap { project.theme(withID: $0)?.id }
    }

    /// Adds a theme, copying `basedOn` if given (else the plain default look), and returns it.
    @discardableResult
    public func addTheme(named name: String, basedOn themeID: UUID? = nil) -> Theme? {
        recordingUndo("New Theme") {
            var theme = Theme(name: name)
            if let themeID {
                guard let source = project.theme(withID: themeID) else {
                    _ = reject(.unknownTheme)
                    return nil
                }
                theme = Theme(name: name, title: source.title, body: source.body, caption: source.caption,
                              background: source.background)
            }
            if let rejection = validate(theme.background) {
                _ = reject(rejection)
                return nil
            }
            project.themes.append(theme)
            lastRejection = nil
            return theme
        }
    }

    /// Replaces the theme with the same ID. Every slide that follows it changes; the audience output changes
    /// when a slide is taken live again.
    @discardableResult
    public func updateTheme(_ theme: Theme) -> CommandResult {
        recordingUndo("Edit Theme", coalescing: "theme-\(theme.id)") {
            guard let index = project.themes.firstIndex(where: { $0.id == theme.id }) else { return reject(.unknownTheme) }
            if let rejection = validate(theme.background) { return reject(rejection) }
            project.themes[index] = theme
            return applied()
        }
    }

    /// Deletes a theme. Presentations that follow it keep their look: it's written into their slides.
    @discardableResult
    public func deleteTheme(_ themeID: UUID) -> CommandResult {
        recordingUndo("Delete Theme") {
            guard let theme = project.theme(withID: themeID) else { return reject(.unknownTheme) }
            for index in project.presentations.indices where project.presentations[index].themeID == themeID {
                project.presentations[index].bakeTheme(theme)
                project.presentations[index].themeID = nil
                project.presentations[index].updatedAt = now()
            }
            project.themes.removeAll { $0.id == themeID }
            if project.defaultThemeID == themeID { project.defaultThemeID = nil }
            Log.coordinator.info("Deleted theme \(themeID, privacy: .public)")
            return applied()
        }
    }

    /// Sets the theme new presentations and songs start with. Nil starts them without one.
    @discardableResult
    public func setDefaultTheme(_ themeID: UUID?) -> CommandResult {
        recordingUndo("Default Theme") {
            if let themeID, project.theme(withID: themeID) == nil { return reject(.unknownTheme) }
            project.defaultThemeID = themeID
            return applied()
        }
    }

    /// True when the presentation has no theme and some of its text is formatted (styled or placed), so applying a
    /// theme should ask whether to keep that formatting.
    public func hasOwnFormatting(_ presentationID: UUID) -> Bool {
        guard let presentation = project.presentation(withID: presentationID), presentation.themeID == nil else { return false }
        return presentation.slides.contains { slide in
            slide.elements.contains { element in
                guard case .text(let text) = element else { return false }
                return text.style != .default(for: text.role) || text.box != nil
            }
        }
    }

    /// Makes a presentation follow a theme, or none.
    ///
    /// - Nil: the presentation keeps the look it has, written into its slides.
    /// - A theme, with `keepSlideFormatting`: text already styled or placed by hand keeps that, the rest follows
    ///   the theme. Switching from another theme keeps what was formatted by hand under it.
    /// - A theme, without: all its text follows the theme.
    @discardableResult
    public func setPresentationTheme(_ themeID: UUID?, presentationID: UUID, keepSlideFormatting: Bool = true) -> CommandResult {
        recordingUndo("Theme") {
            guard let presentation = project.presentation(withID: presentationID), presentationID != project.props.id else {
                return reject(.unknownPresentation)
            }
            if let themeID, project.theme(withID: themeID) == nil { return reject(.unknownTheme) }
            let previous = project.theme(for: presentation)
            return editPresentation(presentationID) { presentation in
                guard let themeID else {
                    if let previous { presentation.bakeTheme(previous) }
                    presentation.themeID = nil
                    return
                }
                for slideIndex in presentation.slides.indices {
                    presentation.slides[slideIndex].elements = presentation.slides[slideIndex].elements.map { element in
                        guard case .text(var text) = element else { return element }
                        if !keepSlideFormatting {
                            text.overrides = []
                        } else if previous == nil {
                            text.overrides = []
                            if text.style != .default(for: text.role) { text.overrides.insert(.style) }
                            if text.box != nil { text.overrides.insert(.box) }
                        }
                        return .text(text)
                    }
                }
                presentation.themeID = themeID
            }
        }
    }

    /// Makes text formatted by hand follow its presentation's theme again. Nil `elementID` does it for every text
    /// element in the presentation.
    @discardableResult
    public func revertToTheme(elementID: UUID?, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Revert to Theme") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard project.theme(for: presentation) != nil else { return reject(.unknownTheme) }
            return editPresentation(presentationID) { presentation in
                for slideIndex in presentation.slides.indices {
                    presentation.slides[slideIndex].elements = presentation.slides[slideIndex].elements.map { element in
                        guard case .text(var text) = element, elementID == nil || text.id == elementID else { return element }
                        text.overrides = []
                        return .text(text)
                    }
                }
            }
        }
    }

    /// Like ProPresenter's "update theme from slide": the text element's style and position become its role's in
    /// the presentation's theme, and the element follows the theme again. Every slide following the theme changes.
    @discardableResult
    public func updateThemeFromText(_ elementID: UUID, slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Update Theme") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard let slide = presentation.slide(withID: slideID) else { return reject(.unknownSlide) }
            guard var theme = project.theme(for: presentation),
                  let themeIndex = project.themes.firstIndex(where: { $0.id == theme.id }) else { return reject(.unknownTheme) }
            guard case .text(let text) = slide.element(withID: elementID) else { return reject(.unknownElement) }
            let look = theme.applied(to: text)
            theme[text.role] = ThemeText(style: look.style, box: look.box)
            project.themes[themeIndex] = theme
            return editSlide(slideID, inPresentation: presentationID) { slide in
                guard let index = slide.elements.firstIndex(where: { $0.id == elementID }),
                      case .text(var updated) = slide.elements[index] else { return }
                updated.overrides = []
                slide.elements[index] = .text(updated)
            }
        }
    }
}
