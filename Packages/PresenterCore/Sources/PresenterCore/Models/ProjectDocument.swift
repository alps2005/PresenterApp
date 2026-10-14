import Foundation

/// Top-level container for a show: the presentation library and the playlist that runs it.
public struct ProjectDocument: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var name: String
    public var schemaVersion: Int
    public var presentations: [PresentationDocument]
    public var playlist: PlaylistDocument
    /// Media files the project's slides reference. The files live in the media library folder.
    public var mediaAssets: [MediaAsset]

    public init(
        id: UUID = UUID(),
        name: String,
        schemaVersion: Int = ProjectDocument.currentSchemaVersion,
        presentations: [PresentationDocument] = [],
        playlist: PlaylistDocument = PlaylistDocument(title: "Service"),
        mediaAssets: [MediaAsset] = []
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.presentations = presentations
        self.playlist = playlist
        self.mediaAssets = mediaAssets
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, schemaVersion, presentations, playlist, mediaAssets
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        presentations = try container.decode([PresentationDocument].self, forKey: .presentations)
        playlist = try container.decode(PlaylistDocument.self, forKey: .playlist)
        mediaAssets = try container.decodeIfPresent([MediaAsset].self, forKey: .mediaAssets) ?? []
    }

    public func asset(withID assetID: UUID) -> MediaAsset? {
        mediaAssets.first { $0.id == assetID }
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

    /// The slide with its background resolved: the slide's own, else its presentation's.
    public func renderedSlide(at position: SlidePosition) -> RenderedSlide? {
        guard let presentation = presentation(forItem: position.itemID),
              let slide = presentation.slide(withID: position.slideID) else { return nil }
        return presentation.rendered(slide)
    }
}

/// Identifies one slide within one playlist entry. Uses stable IDs, never indices.
public struct SlidePosition: Codable, Hashable, Sendable {
    public var itemID: UUID
    public var slideID: UUID
    /// Which time the slide plays in its presentation's arrangement (0 = first). Repeats of a chorus are
    /// distinct positions, so Next and Previous step through them.
    public var occurrence: Int

    public init(itemID: UUID, slideID: UUID, occurrence: Int = 0) {
        self.itemID = itemID
        self.slideID = slideID
        self.occurrence = occurrence
    }

    private enum CodingKeys: String, CodingKey {
        case itemID, slideID, occurrence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decode(UUID.self, forKey: .itemID)
        slideID = try container.decode(UUID.self, forKey: .slideID)
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 0
    }
}
