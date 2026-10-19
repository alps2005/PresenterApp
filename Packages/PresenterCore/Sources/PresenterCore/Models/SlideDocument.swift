import Foundation

/// A single slide: an ordered list of visual elements plus optional operator notes.
public struct SlideDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var elements: [SlideElement]
    public var notes: String?
    /// Overrides the presentation's background. Nil inherits it.
    public var background: SlideBackground?
    /// How the audience output changes to this slide. Nil cuts instantly.
    public var transition: SlideTransition?
    /// A group name such as "Verse 1" or "Chorus", shown on the slide's thumbnail. Never shown to the audience.
    public var label: String?
    /// Moves the live slide on by itself after a while. Nil leaves it to the operator, or to the presentation's
    /// Slideshow interval.
    public var goToNext: GoToNextTimer?
    /// Starts or stops audio when the slide is taken live. Nil leaves the audio alone.
    public var audioCue: AudioCue?

    public init(
        id: UUID = UUID(),
        elements: [SlideElement] = [],
        notes: String? = nil,
        background: SlideBackground? = nil,
        transition: SlideTransition? = nil,
        label: String? = nil,
        goToNext: GoToNextTimer? = nil,
        audioCue: AudioCue? = nil
    ) {
        self.id = id
        self.elements = elements
        self.notes = notes
        self.background = background
        self.transition = transition
        self.label = label
        self.goToNext = goToNext
        self.audioCue = audioCue
    }

    public func element(withID elementID: UUID) -> SlideElement? {
        elements.first { $0.id == elementID }
    }

    /// Convenience for the common case of a slide holding one block of body text.
    public static func text(_ text: String, role: TextRole = .body, notes: String? = nil) -> SlideDocument {
        SlideDocument(elements: [.text(TextElement(text: text, role: role))], notes: notes)
    }

    /// The text of the first text element: what the slide editor edits.
    public var primaryText: String {
        for case .text(let element) in elements { return element.text }
        return ""
    }

    /// The first text element: what the slide editor and inspector edit.
    public var primaryTextElement: TextElement? {
        for case .text(let element) in elements { return element }
        return nil
    }

    /// All text on the slide, joined by newlines.
    public var plainText: String {
        elements.compactMap { element in
            if case .text(let text) = element { return text.text }
            return nil
        }
        .joined(separator: "\n")
    }
}

/// A visual element on a slide. Elements later in a slide's list draw on top of earlier ones.
public enum SlideElement: Identifiable, Codable, Hashable, Sendable {
    case text(TextElement)
    case shape(ShapeElement)
    case image(ImageElement)

    public var id: UUID {
        switch self {
        case .text(let element): element.id
        case .shape(let element): element.id
        case .image(let element): element.id
        }
    }
}

public struct TextElement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var role: TextRole
    public var style: TextStyle
    /// Where the text sits on the canvas. Nil keeps the default centred flow layout.
    public var box: TextBox?
    /// What the operator formatted by hand, so the presentation's theme leaves it alone. The rest follows the theme;
    /// with no theme, `style` and `box` are used as they are.
    public var overrides: Set<ThemedProperty>
    /// Its own transitions as the slide arrives and leaves. Nil follows the slide.
    public var transitionIn: ElementTransition?
    public var transitionOut: ElementTransition?

    public init(
        id: UUID = UUID(),
        text: String,
        role: TextRole = .body,
        style: TextStyle? = nil,
        box: TextBox? = nil,
        overrides: Set<ThemedProperty> = [],
        transitionIn: ElementTransition? = nil,
        transitionOut: ElementTransition? = nil
    ) {
        self.id = id
        self.text = text
        self.role = role
        self.style = style ?? .default(for: role)
        self.box = box
        self.overrides = overrides
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, role, style, box, overrides, transitionIn, transitionOut
    }

    /// Text saved before styling existed has no style; it gets its role's default look. Text saved before themes
    /// existed has no overrides, and text saved before element transitions has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        role = try container.decode(TextRole.self, forKey: .role)
        style = try container.decodeIfPresent(TextStyle.self, forKey: .style) ?? .default(for: role)
        box = try container.decodeIfPresent(TextBox.self, forKey: .box)
        overrides = try container.decodeIfPresent(Set<ThemedProperty>.self, forKey: .overrides) ?? []
        transitionIn = try container.decodeIfPresent(ElementTransition.self, forKey: .transitionIn)
        transitionOut = try container.decodeIfPresent(ElementTransition.self, forKey: .transitionOut)
    }
}

public enum TextRole: String, Codable, Hashable, Sendable, CaseIterable {
    case title
    case body
    case caption
}
