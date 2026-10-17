import Foundation

/// A reusable look for a presentation's slides, like ProPresenter's themes: a text style and position for each text
/// role, and a background. Text that follows the theme changes on every slide when the theme changes; text the
/// operator formats by hand keeps its own look (see `TextElement.overrides`).
public struct Theme: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var title: ThemeText
    public var body: ThemeText
    public var caption: ThemeText
    /// The background for slides that set none, when their presentation sets none either. Nil adds none.
    public var background: SlideBackground?

    public init(
        id: UUID = UUID(),
        name: String,
        title: ThemeText = ThemeText(style: .default(for: .title)),
        body: ThemeText = ThemeText(style: .default(for: .body)),
        caption: ThemeText = ThemeText(style: .default(for: .caption)),
        background: SlideBackground? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.body = body
        self.caption = caption
        self.background = background
    }

    public subscript(role: TextRole) -> ThemeText {
        get {
            switch role {
            case .title: title
            case .body: body
            case .caption: caption
            }
        }
        set {
            switch role {
            case .title: title = newValue
            case .body: body = newValue
            case .caption: caption = newValue
            }
        }
    }

    /// The element as it looks under this theme: the theme's style and position for its role, except where the
    /// operator formatted it by hand.
    public func applied(to element: TextElement) -> TextElement {
        var element = element
        let look = self[element.role]
        if !element.overrides.contains(.style) { element.style = look.style }
        if !element.overrides.contains(.box) { element.box = look.box }
        return element
    }

    /// The slide as it looks under this theme. Shapes and images aren't themed.
    public func applied(to slide: SlideDocument) -> SlideDocument {
        var slide = slide
        slide.elements = slide.elements.map { element in
            guard case .text(let text) = element else { return element }
            return .text(applied(to: text))
        }
        return slide
    }

    /// A few themes to start from, in every new project. Original, so they carry no third-party design.
    public static func presets() -> [Theme] {
        var worship = Theme(name: "Worship")
        worship.body.style.lineSpacing = 8
        worship.background = .color(RGBAColor(red: 0.08, green: 0.10, blue: 0.16))

        // Verses top left, the reference small at the bottom left: easy to read along with.
        var scripture = Theme(name: "Scripture")
        scripture.body = ThemeText(
            style: TextStyle(fontFamily: "Georgia", fontSize: 72, weight: .regular, alignment: .leading, lineSpacing: 10),
            box: .preset(.topLeading)
        )
        scripture.caption = ThemeText(
            style: TextStyle(fontSize: 48, weight: .semibold, color: RGBAColor(red: 0.85, green: 0.85, blue: 0.85),
                             alignment: .leading),
            box: .preset(.bottomLeading)
        )
        scripture.background = .color(RGBAColor(red: 0.12, green: 0.11, blue: 0.10))

        // For a camera feed or stream: words in a dark band along the bottom, no background of its own.
        var lowerThird = Theme(name: "Lower Third")
        lowerThird.body = ThemeText(
            style: TextStyle(fontSize: 64, weight: .semibold, hasShadow: false,
                             backgroundBox: TextBackgroundBox(color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.7))),
            box: .preset(.bottom, margin: 0.06)
        )
        lowerThird.background = .transparent

        return [worship, scripture, lowerThird]
    }
}

/// How a theme styles and places one text role.
public struct ThemeText: Codable, Hashable, Sendable {
    public var style: TextStyle
    /// Nil uses the centred flow layout.
    public var box: TextBox?

    public init(style: TextStyle, box: TextBox? = nil) {
        self.style = style
        self.box = box
    }
}

/// What a text element can take from its presentation's theme.
public enum ThemedProperty: String, Codable, Hashable, Sendable, CaseIterable {
    /// Font, size, colour, alignment and effects.
    case style
    /// Position on the slide.
    case box
}

extension PresentationDocument {
    /// Marks text whose style or position an edit changed away from `theme` as formatted by hand, so the theme
    /// leaves it alone from then on. Called after every edit of a themed presentation, so every way of formatting
    /// text (the inspector, Quick Edit, dragging, Apply to All Slides, paste) counts the same.
    ///
    /// A change counts when the new value differs both from what was stored and from the theme's: views may write
    /// back either the stored element or the themed one they drew, unchanged, along with new words.
    public mutating func recordFormattingOverrides(since before: PresentationDocument, theme: Theme) {
        var previous: [UUID: TextElement] = [:]
        for slide in before.slides {
            for case .text(let text) in slide.elements { previous[text.id] = text }
        }
        for slideIndex in slides.indices {
            for elementIndex in slides[slideIndex].elements.indices {
                guard case .text(var text) = slides[slideIndex].elements[elementIndex] else { continue }
                let look = theme[text.role]
                if let old = previous[text.id] {
                    if text.style != old.style, text.style != look.style { text.overrides.insert(.style) }
                    if text.box != old.box, text.box != look.box { text.overrides.insert(.box) }
                } else {
                    // New text (a new slide, a paste): plain default text follows the theme; anything set by hand doesn't.
                    if text.style != .default(for: text.role), text.style != look.style { text.overrides.insert(.style) }
                    if text.box != nil, text.box != look.box { text.overrides.insert(.box) }
                }
                slides[slideIndex].elements[elementIndex] = .text(text)
            }
        }
    }

    /// The slides with `theme`'s look written into each text element, which then keeps it without the theme.
    /// The theme's background becomes the presentation's when it has none.
    public mutating func bakeTheme(_ theme: Theme) {
        slides = slides.map { slide in
            var slide = theme.applied(to: slide)
            slide.elements = slide.elements.map { element in
                guard case .text(var text) = element else { return element }
                text.overrides = []
                return .text(text)
            }
            return slide
        }
        if background == nil { background = theme.background }
    }
}
