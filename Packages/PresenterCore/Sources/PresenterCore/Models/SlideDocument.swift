import Foundation

/// A single slide: an ordered list of visual elements plus optional operator notes.
public struct SlideDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var elements: [SlideElement]
    public var notes: String?

    public init(id: UUID = UUID(), elements: [SlideElement] = [], notes: String? = nil) {
        self.id = id
        self.elements = elements
        self.notes = notes
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

    public init(id: UUID = UUID(), text: String, role: TextRole = .body) {
        self.id = id
        self.text = text
        self.role = role
    }
}

public enum TextRole: String, Codable, Hashable, Sendable, CaseIterable {
    case title
    case body
    case caption
}
