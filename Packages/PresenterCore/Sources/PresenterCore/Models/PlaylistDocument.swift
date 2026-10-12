import Foundation

/// An ordered service running order. Items reference library presentations by ID,
/// so the same presentation can appear more than once.
public struct PlaylistDocument: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var items: [PresentationItem]

    public init(id: UUID = UUID(), title: String, items: [PresentationItem] = []) {
        self.id = id
        self.title = title
        self.items = items
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
