import Foundation

/// Reads OpenLyrics XML (openlyrics.org), the open song format OpenLP, Worship Extreme and others export:
/// `<song><properties>` with titles, authors, copyright, `ccliNo` and `verseOrder`, then `<lyrics>` with one `<verse>`
/// per section, each with one or more `<lines>` (one slide each) broken by `<br/>`. Chords are dropped, the words
/// inside them kept; comments are dropped. A song in several languages keeps the first. External entities are never
/// resolved.
enum OpenLyricsParser {
    /// True for XML whose root element is `song`.
    static func looksLikeOpenLyrics(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(2048), as: UTF8.self)
        guard let start = head.range(of: #"<(?![?!])[A-Za-z_:][\w:.-]*"#, options: .regularExpression) else { return false }
        let root = head[start].dropFirst().split(separator: ":").last.map(String.init) ?? ""
        return root == "song"
    }

    static func parse(_ data: Data) throws(SongImporter.ImportError) -> ImportedSong {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else {
            throw .malformed(parser.parserError?.localizedDescription ?? "Unknown error")
        }
        var song = ImportedSong(
            title: delegate.titles.first ?? "",
            info: SongInfo(authors: delegate.authors,
                           copyright: SongInfo.copyright(from: delegate.copyright),
                           ccliNumber: SongInfo.ccliNumber(from: delegate.ccliNumber)),
            sections: delegate.sections,
            order: delegate.verseOrder.split(whereSeparator: \.isWhitespace).map { label(forVerseName: String($0)) }
        )
        song.numberRepeatedLabels()
        return song
    }

    /// "v1" → "Verse 1", "c" → "Chorus", "p2" → "Pre-Chorus 2". Other names are kept, capitalized.
    static func label(forVerseName name: String) -> String {
        let lowered = name.lowercased()
        let letters = lowered.prefix { $0.isLetter }
        let rest = lowered.dropFirst(letters.count)
        let words: [Substring: String] = [
            "v": "Verse", "c": "Chorus", "p": "Pre-Chorus", "b": "Bridge", "e": "Ending", "i": "Intro", "o": "Other",
        ]
        guard let word = words[letters] else { return name.capitalized }
        // "v1a" (a part of verse 1) keeps its letter: "Verse 1a".
        return rest.isEmpty ? word : "\(word) \(rest)"
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var titles: [String] = []
        var authors: [String] = []
        var copyright = ""
        var ccliNumber = ""
        var verseOrder = ""
        var sections: [ImportedSong.Section] = []

        /// The property element being read and its text.
        private var property: String?
        private var propertyText = ""
        /// The language of the first verse; verses in other languages are translations, skipped.
        private var language: String?
        private var verseNames: Set<String> = []
        private var inVerse = false
        private var skippingVerse = false
        /// The `<lines>` being read: finished lines, and the current line's text.
        private var lines: [String]?
        private var line = ""
        /// Inside `<comment>`, whose text never goes on a slide.
        private var commentDepth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            if skippingVerse { return }
            switch name {
            case "title", "author", "copyright", "ccliNo", "verseOrder":
                guard !inVerse else { break }
                property = name
                propertyText = ""
            case "verse":
                startVerse(name: attributes["name"] ?? "", language: attributes["lang"])
            case "lines":
                guard inVerse else { break }
                lines = []
                line = ""
            case "br":
                breakLine()
            case "comment":
                commentDepth += 1
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if skippingVerse {
                if name == "verse" { skippingVerse = false }
                return
            }
            switch name {
            case "title", "author", "copyright", "ccliNo", "verseOrder":
                guard property == name else { break }
                finishProperty(name, propertyText.trimmingCharacters(in: .whitespacesAndNewlines))
                property = nil
            case "line":
                // OpenLyrics 0.7 put each line in its own element.
                breakLine()
            case "lines":
                guard var finished = lines else { break }
                breakLine(into: &finished)
                if !sections.isEmpty { sections[sections.count - 1].slides.append(finished) }
                lines = nil
            case "verse":
                inVerse = false
            case "comment":
                commentDepth = max(commentDepth - 1, 0)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !skippingVerse, commentDepth == 0 else { return }
            if property != nil { propertyText += string }
            // Line breaks in the file are only layout: `<br/>` breaks lines.
            if lines != nil { line += string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
        }

        private func startVerse(name: String, language verseLanguage: String?) {
            if language == nil { language = verseLanguage ?? "" }
            // A translation of a verse already read, or a verse in another language.
            if (verseLanguage ?? "") != language || verseNames.contains(name) {
                skippingVerse = true
                return
            }
            verseNames.insert(name)
            inVerse = true
            sections.append(ImportedSong.Section(label: name.isEmpty ? nil : OpenLyricsParser.label(forVerseName: name),
                                                 slides: []))
        }

        private func breakLine() {
            guard var current = lines else { return }
            breakLine(into: &current)
            lines = current
        }

        private func breakLine(into lines: inout [String]) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append(text) }
            line = ""
        }

        private func finishProperty(_ name: String, _ text: String) {
            guard !text.isEmpty else { return }
            switch name {
            case "title": titles.append(text)
            case "author": authors.append(text)
            case "copyright": copyright = text
            case "ccliNo": ccliNumber = text
            case "verseOrder": verseOrder = text
            default: break
            }
        }
    }
}
