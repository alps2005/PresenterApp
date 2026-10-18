import Foundation

/// A Bible reference such as "Juan 3:16-18", "1 Co 13:4-7", "Jn 3:16", "Psalm 23" or "Mateo 5:3-12; 6:9-13".
/// Parsing checks only the shape; whether the chapters and verses exist depends on the translation.
public struct ScriptureReference: Hashable, Sendable {
    /// A chapter, or a verse in it.
    public struct Point: Hashable, Sendable, Comparable {
        public var chapter: Int
        /// Nil is the whole chapter: from its first verse when it starts a range, to its last when it ends one.
        public var verse: Int?

        public init(chapter: Int, verse: Int? = nil) {
            self.chapter = chapter
            self.verse = verse
        }

        public static func < (lhs: Point, rhs: Point) -> Bool {
            (lhs.chapter, lhs.verse ?? 0) < (rhs.chapter, rhs.verse ?? 0)
        }
    }

    /// From one point to another, inclusive. A single verse or chapter starts and ends at the same point.
    public struct Span: Hashable, Sendable {
        public var from: Point
        public var to: Point

        public init(from: Point, to: Point) {
            self.from = from
            self.to = to
        }
    }

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        /// No chapter given ("Juan").
        case missingChapter(BibleBook)
        case unknownBook(String)
        case ambiguousBook(String, [BibleBook])
        /// The numbers after the book don't read as chapters and verses.
        case unreadable(String)
        /// A range that ends before it starts ("Juan 3:18-16").
        case backwards(String)

        public func message(in language: BibleLanguage) -> String {
            let spanish = language == .spanish
            switch self {
            case .empty:
                return spanish ? "Escribe una referencia, como Juan 3:16." : "Type a reference, like John 3:16."
            case .missingChapter(let book):
                return spanish ? "Falta el capítulo: \(book.spanish) 1." : "Add a chapter: \(book.english) 1."
            case .unknownBook(let typed):
                return spanish ? "No hay un libro llamado “\(typed)”." : "There's no book called “\(typed)”."
            case .ambiguousBook(let typed, let books):
                let names = books.map { $0.name(in: language) }.joined(separator: ", ")
                return spanish ? "“\(typed)” puede ser \(names)." : "“\(typed)” could be \(names)."
            case .unreadable(let part):
                return spanish ? "No se entiende “\(part)”. Usa capítulo:versículo, como 3:16-18."
                    : "Can't read “\(part)”. Use chapter:verse, like 3:16-18."
            case .backwards(let part):
                return spanish ? "“\(part)” termina antes de empezar." : "“\(part)” ends before it starts."
            }
        }
    }

    public var book: BibleBook
    public var spans: [Span]

    public init(book: BibleBook, spans: [Span]) {
        self.book = book
        self.spans = spans
    }

    // MARK: Parsing

    public static func parse(_ text: String) throws(ParseError) -> ScriptureReference {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        // The book is everything before the first digit that follows a letter, so "1 Co 13:4" splits at "13".
        var sawLetter = false
        var split = trimmed.endIndex
        for index in trimmed.indices {
            let character = trimmed[index]
            if character.isLetter { sawLetter = true }
            if sawLetter, character.isNumber {
                split = index
                break
            }
        }
        let bookPart = trimmed[..<split].trimmingCharacters(in: .whitespaces)
        let numbers = trimmed[split...].trimmingCharacters(in: .whitespaces)

        let book: BibleBook
        switch BibleBookLookup.match(bookPart) {
        case .book(let found): book = found
        case .ambiguous(let books): throw .ambiguousBook(bookPart, books)
        case .none: throw .unknownBook(bookPart)
        }
        guard !numbers.isEmpty else { throw .missingChapter(book) }
        let spans = try spans(in: numbers)
        guard !spans.isEmpty else { throw .missingChapter(book) }
        return ScriptureReference(book: book, spans: spans)
    }

    /// "3:16-18, 20; 4:1–5:2" → spans. A comma continues the chapter of the verse before it; a semicolon (or a comma
    /// after whole chapters) starts with a chapter.
    private static func spans(in text: String) throws(ParseError) -> [Span] {
        var result: [Span] = []
        let normalized = text.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: ".", with: ":")
            .filter { !$0.isWhitespace }
        // Stray commas and semicolons ("3:16,") are ignored.
        for segment in normalized.split(separator: ";") {
            // The chapter verses after a comma belong to; nil while the segment lists whole chapters.
            var chapter: Int?
            for item in segment.split(separator: ",") {
                let item = String(item)
                let ends = item.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard (1...2).contains(ends.count), let start = point(ends[0], chapter: chapter) else {
                    throw .unreadable(item)
                }
                if start.verse != nil { chapter = start.chapter }
                var end = start
                if ends.count == 2 {
                    guard let parsed = point(ends[1], chapter: start.verse != nil ? start.chapter : nil) else {
                        throw .unreadable(item)
                    }
                    end = parsed
                }
                guard start <= end else { throw .backwards(item) }
                result.append(Span(from: start, to: end))
            }
        }
        return result
    }

    /// "16" (a verse of `chapter`, or a chapter when there's none), or "3:16".
    private static func point(_ text: String, chapter: Int?) -> Point? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0 > 0 }) else { return nil }
        switch numbers.count {
        case 1: return chapter.map { Point(chapter: $0, verse: numbers[0]) } ?? Point(chapter: numbers[0])
        case 2: return Point(chapter: numbers[0], verse: numbers[1])
        default: return nil
        }
    }

    // MARK: Formatting

    /// "Juan 3:16-18", "John 3:16, 18; 4:1", "Psalms 23", "John 3:16–4:2".
    public func formatted(in language: BibleLanguage) -> String {
        "\(book.name(in: language)) \(formattedNumbers)"
    }

    /// Just the chapters and verses: "3:16-18, 20".
    public var formattedNumbers: String {
        var text = ""
        var previousChapter: Int?
        for span in spans {
            let sameChapter = span.from.chapter == previousChapter && span.from.verse != nil
            if !text.isEmpty { text += sameChapter ? ", " : "; " }
            text += Self.format(span, omittingChapter: sameChapter)
            previousChapter = span.to.verse == nil ? nil : span.to.chapter
        }
        return text
    }

    private static func format(_ span: Span, omittingChapter: Bool) -> String {
        let from = span.from, to = span.to
        let start = from.verse.map { omittingChapter ? "\($0)" : "\(from.chapter):\($0)" } ?? "\(from.chapter)"
        if from == to { return start }
        switch (from.verse, to.verse) {
        case (nil, nil): return "\(start)-\(to.chapter)"
        case (.some, .some(let verse)) where from.chapter == to.chapter: return "\(start)-\(verse)"
        default: return "\(start)–\(to.chapter)" + (to.verse.map { ":\($0)" } ?? "")
        }
    }
}
