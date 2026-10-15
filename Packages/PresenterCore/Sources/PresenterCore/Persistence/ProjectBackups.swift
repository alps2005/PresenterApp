import Foundation

/// Dated copies of the project in a `Backups` folder next to the project file, so the operator can get back
/// a project that a bad edit or an Open replaced. Only the newest `limit` copies are kept.
public struct ProjectBackups: Sendable {
    public static let defaultLimit = 10

    public let directory: URL
    public let limit: Int

    public init(projectFileURL: URL, limit: Int = ProjectBackups.defaultLimit) {
        directory = projectFileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        self.limit = limit
    }

    /// `Project-<seconds since 1970>.json`, so names sort by age.
    public static func filename(at date: Date) -> String {
        "Project-\(Int(date.timeIntervalSince1970)).json"
    }

    /// When a backup was made, read from its name, or nil if the name isn't a backup's.
    public static func date(fromFilename name: String) -> Date? {
        guard name.hasPrefix("Project-"), name.hasSuffix(".json") else { return nil }
        let stamp = name.dropFirst("Project-".count).dropLast(".json".count)
        guard let seconds = Int(stamp) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// The backups to delete so only the newest `limit` remain. Files that aren't backups are never listed.
    public static func filenamesToPrune(_ filenames: [String], keeping limit: Int) -> [String] {
        let backups = filenames
            .compactMap { name in date(fromFilename: name).map { (name: name, date: $0) } }
            .sorted { $0.date > $1.date }
        return backups.dropFirst(max(limit, 0)).map(\.name)
    }

    /// Saves `project` as a new backup and prunes old ones. Returns the backup's URL.
    @discardableResult
    public func save(_ project: ProjectDocument, now: Date = .now) throws -> URL {
        let url = directory.appendingPathComponent(Self.filename(at: now))
        try ProjectStore(fileURL: url).save(project)
        prune()
        return url
    }

    /// Copies the project file as it is on disk, unless the newest backup already matches it, and prunes old
    /// ones. Returns the new backup, or nil if there was nothing to back up or no change since the last backup.
    @discardableResult
    public func backUpFile(at projectFileURL: URL, now: Date = .now) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectFileURL.path) else { return nil }
        if let newest = newestBackup(), fileManager.contentsEqual(atPath: newest.path, andPath: projectFileURL.path) {
            return nil
        }
        let url = directory.appendingPathComponent(Self.filename(at: now))
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try fileManager.copyItem(at: projectFileURL, to: url)
        } catch {
            throw ProjectStoreError.writeFailed(error.localizedDescription)
        }
        prune()
        return url
    }

    /// Deletes all but the newest `limit` backups. Failures are ignored; a stale backup is harmless.
    public func prune() {
        for name in Self.filenamesToPrune(filenames(), keeping: limit) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func filenames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func newestBackup() -> URL? {
        filenames()
            .compactMap { name in Self.date(fromFilename: name).map { (name: name, date: $0) } }
            .max { $0.date < $1.date }
            .map { directory.appendingPathComponent($0.name) }
    }
}
