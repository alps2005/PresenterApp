import Foundation

/// The imported Bible translations, kept in one folder outside the project (`Application Support/Presenter/Bibles`):
/// one JSON file per translation plus a small index, so listing them doesn't read whole Bibles. Slides made from them
/// are ordinary text, so a project never depends on this folder.
public struct BibleStore: Sendable {
    /// What the list of translations shows, without loading one.
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var abbreviation: String
        public var language: BibleLanguage
        public var verseCount: Int
    }

    public enum StoreError: Error, Equatable, Sendable {
        case notFound
        case unreadable(String)
        case writeFailed(String)
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// The translations, in the order they were imported. An unreadable or missing index lists none.
    public func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    public func load(_ id: UUID) throws(StoreError) -> BibleTranslation {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL(for: id))
        } catch {
            throw .notFound
        }
        do {
            return try JSONDecoder().decode(BibleTranslation.self, from: data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    /// Adds the translation, or replaces the one with the same ID (keeping its place in the list).
    @discardableResult
    public func save(_ translation: BibleTranslation) throws(StoreError) -> Entry {
        let entry = Entry(id: translation.id, name: translation.name, abbreviation: translation.abbreviation,
                          language: translation.language, verseCount: translation.verseCount)
        var entries = entries()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(translation).write(to: fileURL(for: translation.id), options: .atomic)
            try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        return entry
    }

    /// Reads a Zefania or OSIS file and saves it as a new translation.
    @discardableResult
    public func importFile(at url: URL) throws -> Entry {
        try importFiles(at: [url])
    }

    /// Reads files, or folders of them, as one new translation: a single Bible file, or a USX Bible's books (a
    /// Digital Bible Library bundle, with its `metadata.xml`).
    @discardableResult
    public func importFiles(at urls: [URL]) throws -> Entry {
        let files = urls.flatMap(Self.bibleFiles(in:))
        let documents = try files.map { try Data(contentsOf: $0) }
        return try save(BibleFileParser.parse(documents))
    }

    /// The file itself, or the XML, USX and USFX files anywhere in a folder, in name order (so books keep their order).
    static func bibleFiles(in url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return [url] }
        let extensions: Set = ["xml", "usx", "usfx"]
        let found = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants])
        return (found?.compactMap { $0 as? URL } ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func delete(_ id: UUID) throws(StoreError) {
        let remaining = entries().filter { $0.id != id }
        do {
            try? FileManager.default.removeItem(at: fileURL(for: id))
            try JSONEncoder().encode(remaining).write(to: indexURL, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }
}
