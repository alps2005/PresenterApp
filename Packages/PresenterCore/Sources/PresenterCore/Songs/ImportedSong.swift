import Foundation

/// A song read from a file, before it becomes a presentation: its words in labelled sections, its credits, and the
/// order the file says to sing the sections in.
public struct ImportedSong: Equatable, Sendable {
    /// A labelled part of the song ("Verse 1", "Chorus"). Each slide is a list of lines.
    public struct Section: Equatable, Sendable {
        public var label: String?
        public var slides: [[String]]

        public init(label: String?, slides: [[String]]) {
            self.label = label
            self.slides = slides
        }
    }

    public var title: String
    public var info: SongInfo
    public var sections: [Section]
    /// Section labels in singing order, repeats allowed. Empty means the sections in file order.
    public var order: [String]
    /// The church's CCLI licence number, when the file carries one (SongSelect's "CCLI License #" line). Not the
    /// song's: it fills in the project's licence number if that's still empty.
    public var licenseNumber = ""

    public init(title: String, info: SongInfo = SongInfo(), sections: [Section], order: [String] = []) {
        self.title = title
        self.info = info
        self.sections = sections
        self.order = order
    }

    /// How many slides the song makes, before long slides are split.
    public var slideCount: Int {
        sections.reduce(0) { $0 + $1.slides.count }
    }

    /// The song's slides, each labelled with its section. `maxLinesPerSlide` splits longer slides; nil keeps them.
    public func slides(maxLinesPerSlide: Int? = nil) -> [SlideDocument] {
        sections.flatMap { section in
            section.slides.flatMap { lines in
                let size = max(maxLinesPerSlide ?? lines.count, 1)
                return stride(from: 0, to: lines.count, by: size).map { start in
                    var slide = SlideDocument.text(lines[start..<min(start + size, lines.count)].joined(separator: "\n"))
                    slide.label = section.label
                    return slide
                }
            }
        }
    }

    /// The file's singing order as an arrangement, or nil when it's just the sections in file order (which plays
    /// without one) or names no section the song has.
    public var arrangement: Arrangement? {
        let labels = Set(sections.compactMap(\.label))
        let groups = order.filter(labels.contains)
        guard !groups.isEmpty else { return nil }
        var natural: [String] = []
        for label in sections.compactMap(\.label) where natural.last != label { natural.append(label) }
        guard groups != natural else { return nil }
        return Arrangement(name: "Song Order", groups: groups)
    }

    /// Numbers labels that several different sections share ("Chorus", "Chorus" → "Chorus 1", "Chorus 2"), so each
    /// is its own group, and maps the order's plain label to the first of them.
    mutating func numberRepeatedLabels() {
        var counts: [String: Int] = [:]
        for case let label? in sections.map(\.label) { counts[label, default: 0] += 1 }
        let repeated = Set(counts.filter { $0.value > 1 }.keys)
        guard !repeated.isEmpty else { return }
        var seen: [String: Int] = [:]
        for index in sections.indices {
            guard let label = sections[index].label, repeated.contains(label) else { continue }
            seen[label, default: 0] += 1
            sections[index].label = "\(label) \(seen[label]!)"
        }
        order = order.map { repeated.contains($0) ? "\($0) 1" : $0 }
    }
}

/// Reads song files: OpenLyrics XML, ProPresenter 7 (.pro), ChordPro, and SongSelect's lyrics (.txt) and SongPro
/// (.usr) downloads. Any other text file is read as plain lyrics, as New Song reads pasted words.
public enum SongImporter {
    public enum ImportError: Error, Equatable, Sendable {
        /// Not text, or not a song this app can read.
        case unreadable
        /// The XML is broken, with the parser's description.
        case malformed(String)
        /// A song file with no words.
        case noLyrics
    }

    /// File extensions the import panel offers.
    public static let fileExtensions = ["xml", "cho", "chordpro", "chopro", "crd", "pro", "txt", "usr"]

    /// Reads one file. `fileName` (with its extension) tells ChordPro from plain text and titles a song whose file
    /// doesn't name it.
    public static func parse(_ data: Data, fileName: String) throws(ImportError) -> ImportedSong {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        var song: ImportedSong
        if OpenLyricsParser.looksLikeOpenLyrics(data) {
            song = try OpenLyricsParser.parse(data)
        } else if fileExtension == "pro", ProPresenterParser.isPresentation(data) {
            // .pro is also a ChordPro extension; a ChordPro text file never reads as a ProPresenter one.
            guard let proPresenter = ProPresenterParser.parse(data) else { throw .noLyrics }
            song = proPresenter
        } else {
            guard let text = decodeText(data) else { throw .unreadable }
            if SongSelectParser.looksLikeSongPro(text) {
                song = SongSelectParser.parseSongPro(text)
            } else if SongSelectParser.looksLikeLyricsExport(text) {
                song = SongSelectParser.parseLyricsExport(text)
            } else if ["cho", "chordpro", "chopro", "crd", "pro"].contains(fileExtension) || ChordProParser.looksLikeChordPro(text) {
                song = ChordProParser.parse(text)
            } else if fileExtension == "xml" {
                throw .unreadable
            } else {
                song = plainLyrics(text)
            }
        }
        song.sections = song.sections.compactMap { section in
            let slides = section.slides.filter { !$0.isEmpty }
            return slides.isEmpty ? nil : ImportedSong.Section(label: section.label, slides: slides)
        }
        guard song.slideCount > 0 else { throw .noLyrics }
        if song.title.trimmingCharacters(in: .whitespaces).isEmpty { song.title = name.isEmpty ? "Untitled Song" : name }
        return song
    }

    /// UTF-8 (with or without a byte order mark), UTF-16 with a byte order mark, else Windows Latin 1, which older
    /// song files use.
    static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// Lyrics typed the New Song way: blank lines between slides, section names on their own lines.
    static func plainLyrics(_ text: String) -> ImportedSong {
        var sections: [ImportedSong.Section] = []
        for slide in LyricsParser.slides(from: text) {
            let lines = slide.primaryText.components(separatedBy: "\n")
            if let last = sections.last, last.label == slide.label, slide.label != nil {
                sections[sections.count - 1].slides.append(lines)
            } else {
                sections.append(ImportedSong.Section(label: slide.label, slides: [lines]))
            }
        }
        return ImportedSong(title: "", sections: sections)
    }

    /// Splits lines into slides at blank lines.
    static func stanzas(_ lines: [String]) -> [[String]] {
        var slides: [[String]] = [[]]
        for line in lines {
            if line.isEmpty {
                if !slides[slides.count - 1].isEmpty { slides.append([]) }
            } else {
                slides[slides.count - 1].append(line)
            }
        }
        return slides.filter { !$0.isEmpty }
    }
}
