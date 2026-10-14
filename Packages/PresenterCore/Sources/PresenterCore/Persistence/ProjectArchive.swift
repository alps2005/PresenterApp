import Foundation

/// A project bundled with the image files it uses, as one JSON file, so it can move to another Mac
/// (Export Project…) and open there complete (Open Project…). Plain project files open too.
public enum ProjectArchive {
    public static let currentFormatVersion = 1

    private struct Archive: Codable {
        /// Marks the file as an archive rather than a plain project.
        let presenterArchive: Int
        let project: ProjectDocument
        /// Image bytes keyed by the asset's stored filename.
        let media: [String: Data]
    }

    private struct Header: Decodable {
        struct Version: Decodable { let schemaVersion: Int }
        let presenterArchive: Int
        let project: Version
    }

    /// The project plus every media file it references that exists in `mediaDirectory`.
    /// Files that are missing are left out; those images show as missing after opening, as they did here.
    public static func export(_ project: ProjectDocument, mediaDirectory: URL) throws -> Data {
        var media: [String: Data] = [:]
        for asset in project.mediaAssets {
            let url = mediaDirectory.appendingPathComponent(asset.storedFilename)
            if let data = try? Data(contentsOf: url) { media[asset.storedFilename] = data }
        }
        do {
            return try JSONEncoder().encode(Archive(presenterArchive: currentFormatVersion, project: project, media: media))
        } catch {
            throw ProjectStoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads an exported archive or a plain project file. An archive's images are written into
    /// `mediaDirectory` (files already there are kept) before the project is returned.
    public static func open(_ data: Data, mediaDirectory: URL) throws -> ProjectDocument {
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
            // Not an archive: a project saved by this app or exported by an older version.
            return try ProjectStore.decode(data)
        }
        guard header.presenterArchive <= currentFormatVersion,
              header.project.schemaVersion <= ProjectDocument.currentSchemaVersion else {
            throw ProjectStoreError.newerSchema(
                found: max(header.project.schemaVersion, ProjectDocument.currentSchemaVersion + 1),
                supported: ProjectDocument.currentSchemaVersion
            )
        }
        let archive: Archive
        do {
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch {
            throw ProjectStoreError.unreadable(error.localizedDescription)
        }
        var project = archive.project
        project.schemaVersion = ProjectDocument.currentSchemaVersion

        // Only files the project actually references, by plain filename, so a crafted archive can't write
        // anywhere outside the media folder.
        let expected = Set(project.mediaAssets.map(\.storedFilename))
        do {
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            for (name, bytes) in archive.media where expected.contains(name) && name == (name as NSString).lastPathComponent {
                let destination = mediaDirectory.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try bytes.write(to: destination, options: .atomic)
                }
            }
        } catch {
            throw ProjectStoreError.writeFailed(error.localizedDescription)
        }
        return project
    }
}
