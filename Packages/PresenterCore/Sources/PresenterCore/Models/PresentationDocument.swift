import Foundation

/// A reusable, ordered set of slides stored in the project library.
public struct PresentationDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var slides: [SlideDocument]
    /// The background for every slide that doesn't set its own. Nil uses the app's default background.
    public var background: SlideBackground?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        slides: [SlideDocument] = [],
        background: SlideBackground? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.slides = slides
        self.background = background
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func slide(withID slideID: UUID) -> SlideDocument? {
        slides.first { $0.id == slideID }
    }

    public func index(ofSlide slideID: UUID) -> Int? {
        slides.firstIndex { $0.id == slideID }
    }

    /// A slide of this presentation, ready to draw: its own background, else the presentation's.
    public func rendered(_ slide: SlideDocument) -> RenderedSlide {
        RenderedSlide(slide: slide, background: slide.background ?? background)
    }
}
