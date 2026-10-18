import Foundation

/// Reads a Bible translation from a Zefania XML or OSIS XML file, the free formats public-domain translations are
/// shared in. The format is told by the root element. External entities are never resolved.
public enum BibleFileParser {
    public enum ParseError: Error, Equatable, Sendable {
        /// Not XML, or XML that isn't a Zefania or OSIS Bible.
        case notABible
        /// The XML is broken, with the parser's description.
        case malformed(String)
        /// A Bible file without any verses this app recognizes.
        case noVerses
    }

    public static func parse(_ data: Data) throws(ParseError) -> BibleTranslation {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        let ok = parser.parse()
        guard delegate.format != nil else { throw .notABible }
        guard ok else { throw .malformed(parser.parserError?.localizedDescription ?? "Unknown error") }
        let translation = delegate.translation()
        guard translation.verseCount > 0 else { throw .noVerses }
        return translation
    }

    private enum Format {
        case zefania
        case osis
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var format: Format?
        // Metadata.
        private var title = ""
        private var identifier = ""
        private var languageCode = ""
        private var metadataField: String?
        private var metadataText = ""
        // Verses, by book, chapter and verse number.
        private var verses: [Int: [Int: [Int: String]]] = [:]
        private var book: Int?
        private var chapter: Int?
        /// The verse being read, and its text so far.
        private var verse: (book: Int, chapter: Int, number: Int)?
        private var verseText = ""
        /// OSIS milestone verses (`<verse sID=…/>text<verse eID=…/>`) end at their end marker, not their element.
        private var verseIsMilestone = false
        /// Inside notes and non-canonical headings, whose text never goes on a slide.
        private var skipDepth = 0
        private var bookNames: [String] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if format == nil {
                switch name {
                case "XMLBIBLE": format = .zefania
                case "osis": format = .osis
                default: parser.abortParsing()
                }
                return
            }
            if skipDepth > 0 {
                skipDepth += 1
                return
            }
            switch format {
            case .zefania: startZefania(name, attributes)
            case .osis: startOSIS(name, attributes)
            case nil: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if skipDepth > 0 {
                skipDepth -= 1
                return
            }
            if let field = metadataField, field == name {
                store(metadata: field, metadataText)
                metadataField = nil
            }
            switch (format, name) {
            case (.zefania, "VERS"):
                finishVerse()
            case (.osis, "verse") where !verseIsMilestone:
                finishVerse()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            if metadataField != nil { metadataText += string }
            if verse != nil { verseText += string }
        }

        // MARK: Zefania: <XMLBIBLE><INFORMATION>…</INFORMATION><BIBLEBOOK bnumber><CHAPTER cnumber><VERS vnumber>

        private func startZefania(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "title", "identifier", "language":
                startMetadata(name)
            case "BIBLEBOOK":
                book = attributes["bnumber"].flatMap(Int.init)
                if let bookName = attributes["bname"] { bookNames.append(bookName) }
            case "CHAPTER":
                chapter = attributes["cnumber"].flatMap(Int.init)
            case "VERS":
                startVerse(book: book, chapter: chapter, number: attributes["vnumber"].flatMap(Int.init))
            case "NOTE", "XREF":
                skipDepth = 1
            case "BR":
                verseText += " "
            default:
                break
            }
        }

        // MARK: OSIS: <osis><osisText xml:lang><header><work><title>…<div type="book" osisID="Gen">
        // <chapter osisID="Gen.1"><verse osisID="Gen.1.1">…</verse>, or milestones with sID/eID.

        private func startOSIS(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "osisText":
                if let language = attributes["xml:lang"] { languageCode = language }
                if let work = attributes["osisIDWork"], identifier.isEmpty { identifier = work }
            case "title" where book == nil && verse == nil:
                startMetadata("title")
            case "title" where attributes["canonical"] != "true":
                skipDepth = 1
            case "language" where book == nil:
                startMetadata("language")
            case "div" where attributes["type"] == "book":
                book = attributes["osisID"].flatMap(BibleBook.osis)?.number
            case "chapter":
                if attributes["eID"] != nil { return }
                if let id = attributes["osisID"], let parsed = Self.osisNumbers(id), parsed.count >= 2 {
                    book = parsed[0]
                    chapter = parsed[1]
                }
            case "verse":
                if attributes["eID"] != nil {
                    finishVerse()
                    return
                }
                // Combined verses list several IDs ("Gen.1.1 Gen.1.2"); the first one carries the text.
                guard let id = attributes["osisID"]?.split(separator: " ").first,
                      let parsed = Self.osisNumbers(String(id)), parsed.count == 3 else { return }
                finishVerse()
                verseIsMilestone = attributes["sID"] != nil
                startVerse(book: parsed[0], chapter: parsed[1], number: parsed[2])
            case "note":
                skipDepth = 1
            case "lb", "l":
                verseText += " "
            default:
                break
            }
        }

        /// "Gen.1.1" → [1, 1, 1] (book number, chapter, verse).
        private static func osisNumbers(_ id: String) -> [Int]? {
            let parts = id.split(separator: ".")
            guard let first = parts.first, let book = BibleBook.osis(String(first)) else { return nil }
            let numbers = parts.dropFirst().compactMap { Int($0) }
            guard numbers.count == parts.count - 1 else { return nil }
            return [book.number] + numbers
        }

        // MARK: Shared

        private func startMetadata(_ name: String) {
            metadataField = name
            metadataText = ""
        }

        private func store(metadata field: String, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            switch field {
            case "title" where title.isEmpty: title = value
            case "identifier" where identifier.isEmpty: identifier = value
            case "language" where languageCode.isEmpty: languageCode = value
            default: break
            }
        }

        private func startVerse(book: Int?, chapter: Int?, number: Int?) {
            guard let book, let chapter, let number, (1...66).contains(book) else { return }
            verse = (book, chapter, number)
            verseText = ""
        }

        private func finishVerse() {
            defer {
                verse = nil
                verseText = ""
                verseIsMilestone = false
            }
            guard let verse else { return }
            let text = verseText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { return }
            verses[verse.book, default: [:]][verse.chapter, default: [:]][verse.number] = text
        }

        func translation() -> BibleTranslation {
            finishVerse()
            let books = verses.keys.sorted().map { bookNumber in
                BibleTranslation.Book(number: bookNumber, chapters: verses[bookNumber]!.keys.sorted().map { chapterNumber in
                    BibleTranslation.Chapter(number: chapterNumber, verses: verses[bookNumber]![chapterNumber]!.keys.sorted().map {
                        BibleTranslation.Verse(number: $0, text: verses[bookNumber]![chapterNumber]![$0]!)
                    })
                })
            }
            let name = title.isEmpty ? (identifier.isEmpty ? "Imported Bible" : identifier) : title
            return BibleTranslation(name: name, abbreviation: identifier.isEmpty ? name : identifier,
                                    language: language, books: books)
        }

        /// From the file's language code, else from its book names ("Génesis", "Mateo"…).
        private var language: BibleLanguage {
            let code = languageCode.lowercased()
            if code.hasPrefix("es") || code.hasPrefix("spa") || code.contains("spanish") || code.contains("español") {
                return .spanish
            }
            if code.hasPrefix("en") || code.contains("english") { return .english }
            let spanishNames = Set(BibleBook.all.map { BibleBookLookup.normalized($0.spanish) })
            let englishNames = Set(BibleBook.all.map { BibleBookLookup.normalized($0.english) })
            let names = bookNames.map(BibleBookLookup.normalized)
            let spanishCount = names.filter { spanishNames.contains($0) && !englishNames.contains($0) }.count
            let englishCount = names.filter { englishNames.contains($0) && !spanishNames.contains($0) }.count
            return spanishCount > englishCount ? .spanish : .english
        }
    }
}
