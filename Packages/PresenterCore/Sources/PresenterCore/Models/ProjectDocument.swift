import Foundation

/// Top-level container for a show: the presentation library and the playlist that runs it.
public struct ProjectDocument: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var name: String
    public var schemaVersion: Int
    public var presentations: [PresentationDocument]
    public var playlist: PlaylistDocument

    public init(
        id: UUID = UUID(),
        name: String,
        schemaVersion: Int = ProjectDocument.currentSchemaVersion,
        presentations: [PresentationDocument] = [],
        playlist: PlaylistDocument = PlaylistDocument(title: "Service")
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.presentations = presentations
        self.playlist = playlist
    }

    public func presentation(withID presentationID: UUID) -> PresentationDocument? {
        presentations.first { $0.id == presentationID }
    }

    /// The presentation a playlist item points at, or nil if the item or presentation is missing.
    public func presentation(forItem itemID: UUID) -> PresentationDocument? {
        guard let item = playlist.item(withID: itemID) else { return nil }
        return presentation(withID: item.presentationID)
    }

    public func slide(at position: SlidePosition) -> SlideDocument? {
        presentation(forItem: position.itemID)?.slide(withID: position.slideID)
    }
}

/// Identifies one slide within one playlist entry. Uses stable IDs, never indices.
public struct SlidePosition: Codable, Hashable, Sendable {
    public var itemID: UUID
    public var slideID: UUID

    public init(itemID: UUID, slideID: UUID) {
        self.itemID = itemID
        self.slideID = slideID
    }
}
