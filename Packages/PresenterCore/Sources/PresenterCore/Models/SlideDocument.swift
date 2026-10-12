import Foundation

/// A single slide: an ordered list of visual elements plus optional operator notes.
public struct SlideDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var elements: [SlideElement]
    public var notes: String?
    /// Overrides the presentation's background. Nil inherits it.
    public var background: SlideBackground?

    public init(id: UUID = UUID(), elements: [SlideElement] = [], notes: String? = nil, background: SlideBackground? = nil) {
        self.id = id
        self.elements = elements
        self.notes = notes
        self.background = background
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

/// A visual element on a slide. Only text exists today; images and video arrive with the media milestone.
public enum SlideElement: Identifiable, Codable, Hashable, Sendable {
    case text(TextElement)

    public var id: UUID {
        switch self {
        case .text(let element): element.id
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

    public init(id: UUID = UUID(), text: String, role: TextRole = .body, style: TextStyle? = nil, box: TextBox? = nil) {
        self.id = id
        self.text = text
        self.role = role
        self.style = style ?? .default(for: role)
        self.box = box
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, role, style, box
    }

    /// Text saved before styling existed has no style; it gets its role's default look.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        role = try container.decode(TextRole.self, forKey: .role)
        style = try container.decodeIfPresent(TextStyle.self, forKey: .style) ?? .default(for: role)
        box = try container.decodeIfPresent(TextBox.self, forKey: .box)
    }
}

public enum TextRole: String, Codable, Hashable, Sendable, CaseIterable {
    case title
    case body
    case caption
}
