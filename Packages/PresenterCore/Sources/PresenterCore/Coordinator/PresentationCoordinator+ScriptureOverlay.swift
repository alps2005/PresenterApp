import Foundation

// Scripture over the cued slide: a passage shown live on top of a slide, without adding a presentation. Live: never
// undone or saved.
extension PresentationCoordinator {
    /// The passage's pages of verses, styled by `themeID` (nil, or a deleted theme, the plain look). The theme's look is
    /// written into the text, as when a theme is baked, so an output's look can still restyle it.
    func scripturePages(_ passage: BiblePassage, second: BiblePassage?, options: ScriptureSlides.Options,
                        themeID: UUID?) -> [SlideDocument] {
        let theme = existingThemeID(themeID).flatMap(project.theme(withID:))
        return ScriptureSlides.make(passage, second: second, options: options).map { page in
            var page = theme?.applied(to: page) ?? page
            page.elements = page.elements.map { element in
                guard case .text(var text) = element else { return element }
                text.overrides = []
                return .text(text)
            }
            return page
        }
    }

    /// The base slide with a page of verses on top. Each page has its own ID, so moving between pages plays the base
    /// slide's transition; its elements' In transitions play only with the first page, which brings them on screen.
    static func composed(_ base: RenderedSlide, page: SlideDocument, isFirstPage: Bool) -> RenderedSlide {
        let underneath = base.slide.elements.map { element in
            var element = element
            if !isFirstPage { element[transition: .in] = nil }
            return element
        }
        let slide = SlideDocument(id: page.id, elements: underneath + page.elements, notes: base.slide.notes,
                                  background: base.slide.background, transition: base.slide.transition,
                                  label: base.slide.label)
        return RenderedSlide(slide: slide, background: base.background)
    }

    /// How the passage would look over the cued slide, page by page, as the audience would see it. Empty when nothing
    /// is cued.
    public func scripturePreview(_ passage: BiblePassage, second: BiblePassage? = nil,
                                 options: ScriptureSlides.Options = ScriptureSlides.Options(),
                                 themeID: UUID?) -> [RenderedSlide] {
        guard let base = previewSlide else { return [] }
        let pages = scripturePages(passage, second: second, options: options, themeID: themeID)
        return pages.indices.map { outputPreview(of: Self.composed(base, page: pages[$0], isFirstPage: $0 == 0)) }
    }

    /// Takes the cued slide live with the passage's first page of verses on top. Next and Previous then step through
    /// the pages, and past either end carry on with the show from the cued slide. Nothing is added to the show or
    /// the library. The cued slide's automatic advancing is cancelled, so it can't take the verses away.
    @discardableResult
    public func showScripture(_ passage: BiblePassage, second: BiblePassage? = nil,
                              options: ScriptureSlides.Options = ScriptureSlides.Options(),
                              themeID: UUID?) -> CommandResult {
        guard let position = state.preview else { return reject(.nothingCued) }
        let pages = scripturePages(passage, second: second, options: options, themeID: themeID)
        guard !pages.isEmpty else { return reject(.noVerses) }
        let result = goLive(at: position)
        guard result.isApplied, let live = state.live else { return result }
        let caption = second.map { "\(passage.caption) / \($0.translationAbbreviation)" } ?? passage.caption
        state.scriptureOverlay = ScriptureOverlay(base: position, baseRendered: live.rendered, pages: pages, caption: caption)
        state.live = LiveSlide(position: position, rendered: Self.composed(live.rendered, page: pages[0], isFirstPage: true))
        state.autoAdvance = nil
        Log.coordinator.info("Scripture over the live slide, \(pages.count) pages")
        return applied()
    }

    /// Takes the verses off, leaving the slide under them live on its own.
    @discardableResult
    public func endScripture() -> CommandResult {
        guard let overlay = state.scriptureOverlay, state.live?.position == overlay.base else { return reject(.nothingLive) }
        state.scriptureOverlay = nil
        state.live = LiveSlide(position: overlay.base, rendered: overlay.baseRendered)
        return applied()
    }

    /// The live slide at the overlay's page `index`.
    func showScripturePage(_ index: Int, of overlay: ScriptureOverlay) {
        var overlay = overlay
        overlay.index = index
        state.scriptureOverlay = overlay
        state.live = LiveSlide(position: overlay.base,
                               rendered: Self.composed(overlay.baseRendered, page: overlay.pages[index], isFirstPage: index == 0))
    }

    /// The overlay's next page as it would go live, if there is one.
    var nextScripturePage: RenderedSlide? {
        guard let overlay = state.scriptureOverlay, state.live?.position == overlay.base,
              overlay.pages.indices.contains(overlay.index + 1) else { return nil }
        return Self.composed(overlay.baseRendered, page: overlay.pages[overlay.index + 1], isFirstPage: false)
    }
}
