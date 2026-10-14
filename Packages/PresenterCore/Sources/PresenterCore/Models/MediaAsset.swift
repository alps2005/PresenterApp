import Foundation

/// A media file the project uses. The file itself lives in the media library folder under
/// `storedFilename`; the project only keeps this reference.
public struct MediaAsset: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case image
    }

    public let id: UUID
    public var kind: Kind
    /// The name of the file the operator imported, for display.
    public var originalFilename: String
    /// The name of the copy inside the media library folder.
    public var storedFilename: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind = .image,
        originalFilename: String,
        storedFilename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        importedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.importedAt = importedAt
    }
}
