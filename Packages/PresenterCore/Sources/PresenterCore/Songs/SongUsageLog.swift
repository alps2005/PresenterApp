import Foundation

/// Which songs were shown and when, for a church's CCLI usage report. One line of JSON per use, appended to a file
/// beside the project (not in it, so it isn't undone, exported or replaced by Open Project).
public struct SongUsageLog: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var date: Date
        public var presentationID: UUID
        public var title: String
        public var ccliNumber: String
        public var authors: String

        public init(date: Date, presentationID: UUID, title: String, ccliNumber: String, authors: String) {
            self.date = date
            self.presentationID = presentationID
            self.title = title
            self.ccliNumber = ccliNumber
            self.authors = authors
        }
    }

    /// A song's uses between two dates, as the report lists it.
    public struct Row: Equatable, Sendable, Identifiable {
        public var title: String
        public var ccliNumber: String
        public var authors: String
        public var uses: Int
        public var lastUsed: Date
        public var id: String { ccliNumber.isEmpty ? title : ccliNumber }
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Records a song being shown, once per song per day: a song sung twice in one service is one use.
    public func record(_ presentation: PresentationDocument, at date: Date, calendar: Calendar = .current) throws {
        let entries = (try? self.entries()) ?? []
        guard !entries.contains(where: {
            $0.presentationID == presentation.id && calendar.isDate($0.date, inSameDayAs: date)
        }) else { return }
        let entry = Entry(date: date, presentationID: presentation.id, title: presentation.title,
                          ccliNumber: presentation.song?.ccliNumber ?? "", authors: presentation.song?.authorLine ?? "")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(entry)
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: fileURL, options: .atomic)
        }
    }

    /// Every recorded use, oldest first. A damaged line is skipped rather than losing the rest.
    public func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    /// Uses between `start` and `end` (whole days), one row per song, most used first. Songs are matched by CCLI
    /// number, or by title when they have none.
    public static func report(_ entries: [Entry], from start: Date, to end: Date,
                              calendar: Calendar = .current) -> [Row] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        var rows: [String: Row] = [:]
        for entry in entries where entry.date >= first && entry.date < last {
            let key = entry.ccliNumber.isEmpty ? "title:" + entry.title.lowercased() : entry.ccliNumber
            if var row = rows[key] {
                row.uses += 1
                if entry.date > row.lastUsed {
                    row.lastUsed = entry.date
                    row.title = entry.title
                }
                if row.authors.isEmpty { row.authors = entry.authors }
                rows[key] = row
            } else {
                rows[key] = Row(title: entry.title, ccliNumber: entry.ccliNumber, authors: entry.authors,
                                uses: 1, lastUsed: entry.date)
            }
        }
        return rows.values.sorted {
            $0.uses != $1.uses ? $0.uses > $1.uses : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// The report as CSV, for CCLI's online reporting or a spreadsheet.
    public static func csv(_ rows: [Row], dateFormatter: DateFormatter) -> String {
        func field(_ text: String) -> String {
            text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        let lines = rows.map { row in
            [row.title, row.authors, row.ccliNumber, String(row.uses), dateFormatter.string(from: row.lastUsed)]
                .map(field).joined(separator: ",")
        }
        return (["Title,Writers,CCLI Song Number,Times Used,Last Used"] + lines).joined(separator: "\n") + "\n"
    }
}
