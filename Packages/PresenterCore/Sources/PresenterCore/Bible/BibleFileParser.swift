import Foundation

/// Reads a Bible translation from Zefania XML, OSIS XML, USFX or USX, the free formats public-domain and open
/// translations are shared in. The format is told by each file's root element. USX comes one file per book, so several
/// files can make one translation, named by the Digital Bible Library `metadata.xml` if it's among them. External
/// entities are never resolved.
public enum BibleFileParser {
    public enum ParseError: Error, Equatable, Sendable {
        /// Not XML, or XML that isn't a Zefania, OSIS, USFX or USX Bible.
        case notABible
        /// The XML is broken, with the parser's description.
        case malformed(String)
        /// A Bible file without any verses this app recognizes.
        case noVerses
    }

    public static func parse(_ data: Data) throws(ParseError) -> BibleTranslation {
        try parse([data])
    }

    /// Reads several files as one translation: a USX book per file, say, with or without the bundle's `metadata.xml`.
    /// Files that aren't Bibles are passed over, unless none is.
    public static func parse(_ documents: [Data]) throws(ParseError) -> BibleTranslation {
        let delegate = Delegate()
        for data in documents {
            delegate.beginDocument()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.shouldProcessNamespaces = false
            parser.delegate = delegate
            let ok = parser.parse()
            guard delegate.format != nil else { continue }
            guard ok else { throw .malformed(parser.parserError?.localizedDescription ?? "Unknown error") }
            delegate.endDocument()
        }
        guard delegate.sawBible else { throw .notABible }
        let translation = delegate.translation()
        guard translation.verseCount > 0 else { throw .noVerses }
        return translation
    }

    /// Whether a USFX or USX paragraph style holds something other than verse text (see `Delegate`).
    static func isNonVerseStyle(_ style: String) -> Bool {
        Delegate.isNonVerseStyle(style)
    }

    private enum Format {
        case zefania
        case osis
        case usfx
        case usx
        /// A Digital Bible Library bundle's `metadata.xml`: the translation's name, abbreviation and language.
        case dblMetadata
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var format: Format?
        /// Whether any file so far was a Bible, not just metadata.
        private(set) var sawBible = false
        // Metadata.
        private var title = ""
        private var identifier = ""
        private var languageCode = ""
        /// The element whose text is being read as metadata, and what it is ("title", "identifier", "language").
        private var metadataField: (element: String, key: String)?
        private var metadataText = ""
        /// DBL metadata's open elements, to tell `identification/name` from the other names in it.
        private var elementPath: [String] = []
        /// USFX and USX running heads (`h`), the book names their language is told from.
        private var bookNameText: String?
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

        /// Each file starts with its root element; the verses and metadata read so far carry over.
        func beginDocument() {
            format = nil
            skipDepth = 0
            elementPath = []
        }

        /// A milestone verse runs to the end of its book, which is the end of a USX file.
        func endDocument() {
            finishVerse()
            book = nil
            chapter = nil
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if format == nil {
                switch name {
                case "XMLBIBLE": format = .zefania
                case "osis": format = .osis
                case "usfx": format = .usfx
                case "usx": format = .usx
                case "DBLMetadata": format = .dblMetadata
                default: parser.abortParsing()
                }
                if format != nil && format != .dblMetadata { sawBible = true }
                return
            }
            if skipDepth > 0 {
                skipDepth += 1
                return
            }
            switch format {
            case .zefania: startZefania(name, attributes)
            case .osis: startOSIS(name, attributes)
            case .usfx: startUSFX(name, attributes)
            case .usx: startUSX(name, attributes)
            case .dblMetadata: startDBLMetadata(name)
            case nil: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if skipDepth > 0 {
                skipDepth -= 1
                return
            }
            if let field = metadataField, field.element == name {
                store(metadata: field.key, metadataText)
                metadataField = nil
            }
            switch (format, name) {
            case (.zefania, "VERS"):
                finishVerse()
            case (.osis, "verse") where !verseIsMilestone:
                finishVerse()
            case (.usfx, "h"), (.usx, "para"):
                if let text = bookNameText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    bookNames.append(text)
                }
                bookNameText = nil
            case (.usfx, "book"):
                finishVerse()
            case (.dblMetadata, _):
                // The root element isn't on the path.
                _ = elementPath.popLast()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            if metadataField != nil { metadataText += string }
            if bookNameText != nil {
                bookNameText? += string
                return
            }
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

        // MARK: USFX: <usfx><languageCode>…<book id="GEN"><c id="1"/><v id="1"/>…<ve/>, with notes (<f>, <x>),
        // headings (<s>, <d>) and introductions (<p sfm="ip">) that never reach a slide.

        private func startUSFX(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "languageCode" where book == nil:
                startMetadata(element: name, key: "language")
            case "book":
                finishVerse()
                book = attributes["id"].flatMap(BibleBook.usfm)?.number
                chapter = nil
            case "c":
                finishVerse()
                chapter = attributes["id"].flatMap(Int.init)
            case "v":
                finishVerse()
                verseIsMilestone = true
                startVerse(book: book, chapter: chapter, number: attributes["id"].flatMap(Self.firstNumber))
            case "ve":
                finishVerse()
            case "h":
                bookNameText = ""
            case "f", "fe", "x", "ef", "ex", "s", "d", "id", "ide", "rem", "toc", "cl", "cp", "ca", "va", "vp", "fig", "periph":
                skipDepth = 1
            case "p", "q", "qs", "b":
                if let style = attributes["sfm"] ?? attributes["style"], Self.isNonVerseStyle(style) {
                    skipDepth = 1
                } else {
                    verseText += " "
                }
            default:
                break
            }
        }

        // MARK: USX: <usx><book code="GEN" style="id">…</book><chapter number="1" sid="GEN 1"/><para style="p">
        // <verse number="1" sid="GEN 1:1"/>…<verse eid="GEN 1:1"/></para>, with notes and heading paragraphs skipped.

        private func startUSX(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "book":
                finishVerse()
                book = attributes["code"].flatMap(BibleBook.usfm)?.number
                chapter = nil
                // Its text is a description of the file, not scripture.
                skipDepth = 1
            case "chapter":
                guard attributes["eid"] == nil else { return }
                finishVerse()
                chapter = attributes["number"].flatMap(Int.init)
            case "verse":
                finishVerse()
                guard attributes["eid"] == nil else { return }
                verseIsMilestone = true
                startVerse(book: book, chapter: chapter, number: attributes["number"].flatMap(Self.firstNumber))
            case "para":
                let style = attributes["style"] ?? ""
                if style == "h" {
                    bookNameText = ""
                } else if Self.isNonVerseStyle(style) {
                    skipDepth = 1
                } else {
                    verseText += " "
                }
            case "note", "figure", "sidebar":
                skipDepth = 1
            case "char":
                if ["va", "vp", "ca", "fig"].contains(attributes["style"] ?? "") { skipDepth = 1 }
            case "optbreak":
                verseText += " "
            default:
                break
            }
        }

        // MARK: DBL metadata: <DBLMetadata><identification><name>…<abbreviation>…<language><iso>…

        private func startDBLMetadata(_ name: String) {
            let parent = elementPath.last
            elementPath.append(name)
            switch (parent, name) {
            case ("identification", "name"): startMetadata(element: name, key: "title")
            case ("identification", "abbreviation"): startMetadata(element: name, key: "identifier")
            // The abbreviation readers know ("WEBP"), over the catalogue's ("engwebp").
            case ("identification", "abbreviationLocal"): startMetadata(element: name, key: "localIdentifier")
            case ("language", "iso"): startMetadata(element: name, key: "language")
            default: break
            }
        }

        /// Paragraph styles that aren't verse text: running heads, titles, section headings, references, introductions,
        /// remarks and chapter labels. Psalm titles (`d`) are left out too, as OSIS non-canonical titles are.
        static func isNonVerseStyle(_ style: String) -> Bool {
            let families = ["h", "toc", "mt", "ms", "mr", "s", "sr", "r", "d", "sp", "rem", "ide", "cl", "cd", "restore"]
            if families.contains(where: { style == $0 || (style.hasPrefix($0) && style.dropFirst($0.count).allSatisfy(\.isNumber)) }) {
                return true
            }
            // Introductions: ip, is1, imt, io2, iot, ili…
            return style.hasPrefix("i") && style != "i"
        }

        /// "16" → 16; a verse range "16-17" → 16, its text going to the first verse.
        static func firstNumber(_ text: String) -> Int? {
            Int(text.prefix { $0.isNumber })
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
            startMetadata(element: name, key: name)
        }

        private func startMetadata(element: String, key: String) {
            metadataField = (element, key)
            metadataText = ""
        }

        private func store(metadata field: String, _ value: String) {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            switch field {
            case "title" where title.isEmpty: title = value
            case "identifier" where identifier.isEmpty: identifier = value
            case "localIdentifier": identifier = value
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
