import Foundation

/// An ordered service running order. Items reference library presentations by ID,
/// so the same presentation can appear more than once.
public struct PlaylistDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var items: [PresentationItem]
    /// When the show was last opened, so the Shows window can list the recent ones first. Nil if never.
    public var lastOpenedAt: Date?

    public init(id: UUID = UUID(), title: String, items: [PresentationItem] = [], lastOpenedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.items = items
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, items, lastOpenedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        items = try container.decode([PresentationItem].self, forKey: .items)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }

    public func item(withID itemID: UUID) -> PresentationItem? {
        items.first { $0.id == itemID }
    }

    public func index(ofItem itemID: UUID) -> Int? {
        items.firstIndex { $0.id == itemID }
    }
}

/// One entry in a playlist. Its own ID is distinct from the presentation it points to.
public struct PresentationItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var presentationID: UUID

    public init(id: UUID = UUID(), presentationID: UUID) {
        self.id = id
        self.presentationID = presentationID
    }
}
