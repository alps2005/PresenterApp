import Foundation

public enum ProjectStoreError: Error, Equatable, Sendable {
    /// The file isn't a project this app can read: not JSON, or missing required fields.
    case unreadable(String)
    /// The file was saved by a newer version of the app. Loading it could silently drop data.
    case newerSchema(found: Int, supported: Int)
    case writeFailed(String)

    public var message: String {
        switch self {
        case .unreadable(let detail): "The project file couldn't be read. \(detail)"
        case .newerSchema(let found, let supported):
            "The project was saved by a newer version of Presenter (format \(found); this version reads up to \(supported))."
        case .writeFailed(let detail): "The project couldn't be saved. \(detail)"
        }
    }
}

/// Reads and writes a project as one JSON file. UI-free; the app decides where the file lives and when to save.
public struct ProjectStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The saved project, or nil if nothing has been saved here yet.
    public func load() throws -> ProjectDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ProjectStoreError.unreadable(error.localizedDescription)
        }
        return try Self.decode(data)
    }

    /// Writes atomically, so a crash mid-save leaves the previous file intact.
    public func save(_ project: ProjectDocument) throws {
        do {
            let data = try Self.encode(project)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as ProjectStoreError {
            throw error
        } catch {
            throw ProjectStoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Moves an unreadable file aside so later saves don't overwrite it, and returns where it went.
    @discardableResult
    public func quarantine(now: Date = .now) throws -> URL {
        let stamp = Int(now.timeIntervalSince1970)
        let name = "\(fileURL.deletingPathExtension().lastPathComponent).unreadable-\(stamp).\(fileURL.pathExtension)"
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: fileURL, to: destination)
        return destination
    }

    public static func encode(_ project: ProjectDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    /// Checks the schema version before decoding the whole document, so a newer file is reported
    /// as newer rather than as corrupt.
    public static func decode(_ data: Data) throws -> ProjectDocument {
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()

        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw ProjectStoreError.unreadable(describe(error))
        }
        guard version <= ProjectDocument.currentSchemaVersion else {
            throw ProjectStoreError.newerSchema(found: version, supported: ProjectDocument.currentSchemaVersion)
        }

        do {
            var project = try decoder.decode(ProjectDocument.self, from: data)
            // Older formats load through the Codable defaults; they're saved back at the current version.
            project.schemaVersion = ProjectDocument.currentSchemaVersion
            return project
        } catch {
            throw ProjectStoreError.unreadable(describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context): context.debugDescription
        case DecodingError.keyNotFound(let key, _): "Missing field \"\(key.stringValue)\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "Unexpected value at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        default: error.localizedDescription
        }
    }
}
