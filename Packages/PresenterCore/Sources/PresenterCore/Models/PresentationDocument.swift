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
    /// The project theme its slides follow (see `Theme`). Nil uses each slide's own formatting.
    public var themeID: UUID?
    /// Slideshow: every slide without its own Go To Next timer moves on after this many seconds, and the last slide
    /// loops back to the first. Nil is off.
    public var slideshowInterval: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        slides: [SlideDocument] = [],
        background: SlideBackground? = nil,
        arrangements: [Arrangement] = [],
        activeArrangementID: UUID? = nil,
        themeID: UUID? = nil,
        slideshowInterval: Double? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.slides = slides
        self.background = background
        self.arrangements = arrangements
        self.activeArrangementID = activeArrangementID
        self.themeID = themeID
        self.slideshowInterval = slideshowInterval
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, slides, background, arrangements, activeArrangementID, themeID, slideshowInterval, createdAt, updatedAt
    }

    /// Files saved before arrangements, themes or slideshows existed load with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        slides = try container.decode([SlideDocument].self, forKey: .slides)
        background = try container.decodeIfPresent(SlideBackground.self, forKey: .background)
        arrangements = try container.decodeIfPresent([Arrangement].self, forKey: .arrangements) ?? []
        activeArrangementID = try container.decodeIfPresent(UUID.self, forKey: .activeArrangementID)
        themeID = try container.decodeIfPresent(UUID.self, forKey: .themeID)
        slideshowInterval = try container.decodeIfPresent(Double.self, forKey: .slideshowInterval)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func slide(withID slideID: UUID) -> SlideDocument? {
        slides.first { $0.id == slideID }
    }

    public func index(ofSlide slideID: UUID) -> Int? {
        slides.firstIndex { $0.id == slideID }
    }

    /// A slide of this presentation, ready to draw under `theme` (which should be this presentation's, see
    /// `ProjectDocument.rendered(_:in:)`): text follows the theme where it isn't formatted by hand, and the
    /// background is the slide's own, else the presentation's, else the theme's.
    public func rendered(_ slide: SlideDocument, theme: Theme?) -> RenderedSlide {
        guard let theme else { return RenderedSlide(slide: slide, background: slide.background ?? background) }
        return RenderedSlide(slide: theme.applied(to: slide), background: slide.background ?? background ?? theme.background)
    }
}

extension PresentationDocument {
    /// True when the presentation's background, or any slide's background or image, uses the asset.
    public func uses(_ assetID: UUID) -> Bool {
        background?.assetID == assetID || slides.contains { slide in
            slide.background?.assetID == assetID || slide.elements.contains { $0.assetID == assetID }
        }
    }

    /// Clears backgrounds that use the asset and removes images of it, for deleting it from the project.
    mutating func removeMedia(_ assetID: UUID) {
        if background?.assetID == assetID { background = nil }
        for index in slides.indices {
            if slides[index].background?.assetID == assetID { slides[index].background = nil }
            slides[index].elements.removeAll { $0.assetID == assetID }
        }
    }
}
