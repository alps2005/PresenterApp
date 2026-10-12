import Foundation

/// A reusable, ordered set of slides stored in the project library.
public struct PresentationDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var slides: [SlideDocument]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        slides: [SlideDocument] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.slides = slides
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func slide(withID slideID: UUID) -> SlideDocument? {
        slides.first { $0.id == slideID }
    }

    public func index(ofSlide slideID: UUID) -> Int? {
        slides.firstIndex { $0.id == slideID }
    }
}
