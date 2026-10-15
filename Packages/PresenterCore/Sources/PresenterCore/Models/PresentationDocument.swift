import Foundation

/// A reusable, ordered set of slides stored in the project library.
public struct PresentationDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var slides: [SlideDocument]
    /// The background for every slide that doesn't set its own. Nil uses the app's default background.
    public var background: SlideBackground?
    /// Saved play orders for the presentation's groups (see `Arrangement`).
    public var arrangements: [Arrangement]
    /// The arrangement used when the presentation plays. Nil plays every slide in order.
    public var activeArrangementID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        slides: [SlideDocument] = [],
        background: SlideBackground? = nil,
        arrangements: [Arrangement] = [],
        activeArrangementID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.slides = slides
        self.background = background
        self.arrangements = arrangements
        self.activeArrangementID = activeArrangementID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, slides, background, arrangements, activeArrangementID, createdAt, updatedAt
    }

    /// Files saved before arrangements existed load with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slides = try container.decode([SlideDocument].self, forKey: .slides)
        background = try container.decodeIfPresent(SlideBackground.self, forKey: .background)
        arrangements = try container.decodeIfPresent([Arrangement].self, forKey: .arrangements) ?? []
        activeArrangementID = try container.decodeIfPresent(UUID.self, forKey: .activeArrangementID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
