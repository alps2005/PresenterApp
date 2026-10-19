import Foundation

/// A folder in the library, one level deep. Presentations name the folder they're in (`PresentationDocument.folderID`),
/// so deleting a folder only has to move its presentations back to the top of the library.
public struct LibraryFolder: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
