import Foundation

/// A Bible translation the operator imported from a public-domain file. Stored outside the project (see
/// `BibleStore`); slides made from it are ordinary text slides.
public struct BibleTranslation: Codable, Hashable, Sendable, Identifiable {
    public struct Verse: Codable, Hashable, Sendable {
        public var number: Int
        public var text: String

        public init(number: Int, text: String) {
            self.number = number
            self.text = text
        }
    }

    public struct Chapter: Codable, Hashable, Sendable {
        public var number: Int
        public var verses: [Verse]

        public init(number: Int, verses: [Verse]) {
            self.number = number
            self.verses = verses
        }
    }

    public struct Book: Codable, Hashable, Sendable {
        /// 1 (Genesis) to 66 (Revelation); see `BibleBook`.
        public var number: Int
        public var chapters: [Chapter]

        public init(number: Int, chapters: [Chapter]) {
            self.number = number
            self.chapters = chapters
        }

        public func chapter(_ number: Int) -> Chapter? {
            chapters.first { $0.number == number }
        }
    }

    public var id: UUID
    /// "Reina-Valera 1909".
    public var name: String
    /// "RVR1909", shown after references.
    public var abbreviation: String
    public var language: BibleLanguage
    /// In canonical order. Books the file didn't have are missing.
    public var books: [Book]

    public init(id: UUID = UUID(), name: String, abbreviation: String, language: BibleLanguage, books: [Book]) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.language = language
        self.books = books
    }

    public func book(_ number: Int) -> Book? {
        books.first { $0.number == number }
    }

    public var verseCount: Int {
        books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
    }
}

/// Verses looked up for a reference in one translation.
public struct BiblePassage: Hashable, Sendable {
    public struct Verse: Hashable, Sendable {
        public var chapter: Int
        public var number: Int
        public var text: String
    }

    public var reference: ScriptureReference
    public var translationName: String
    public var translationAbbreviation: String
    public var language: BibleLanguage
    /// In reading order, without repeats.
    public var verses: [Verse]

    /// "Juan 3:16-18 · RVR1909".
    public var caption: String {
        "\(reference.formatted(in: language)) · \(translationAbbreviation)"
    }
}

public enum BiblePassageError: Error, Equatable, Sendable {
    case bookMissing(BibleBook)
    case chapterMissing(BibleBook, Int)
    case verseMissing(BibleBook, chapter: Int, verse: Int)

    public func message(in language: BibleLanguage) -> String {
        let spanish = language == .spanish
        switch self {
        case .bookMissing(let book):
            let name = book.name(in: language)
            return spanish ? "Esta traducción no tiene \(name)." : "This translation doesn't have \(name)."
        case .chapterMissing(let book, let chapter):
            let name = book.name(in: language)
            return spanish ? "\(name) no tiene capítulo \(chapter)." : "\(name) has no chapter \(chapter)."
        case .verseMissing(let book, let chapter, let verse):
            let name = book.name(in: language)
            return spanish ? "\(name) \(chapter) no tiene versículo \(verse)." : "\(name) \(chapter) has no verse \(verse)."
        }
    }
}

extension BibleTranslation {
    /// The verses a reference covers, checking each chapter and verse exists.
    public func passage(for reference: ScriptureReference) throws(BiblePassageError) -> BiblePassage {
        guard let book = book(reference.book.number) else { throw .bookMissing(reference.book) }
        var verses: [BiblePassage.Verse] = []
        var seen = Set<[Int]>()
        for span in reference.spans {
            for chapterNumber in span.from.chapter...span.to.chapter {
                guard let chapter = book.chapter(chapterNumber), let last = chapter.verses.last?.number else {
                    throw .chapterMissing(reference.book, chapterNumber)
                }
                let first = chapterNumber == span.from.chapter ? span.from.verse ?? 1 : 1
                let end = chapterNumber == span.to.chapter ? span.to.verse ?? last : last
                for wanted in [first, end] where !chapter.verses.contains(where: { $0.number == wanted }) {
                    throw .verseMissing(reference.book, chapter: chapterNumber, verse: wanted)
                }
                for verse in chapter.verses where (first...end).contains(verse.number) && seen.insert([chapterNumber, verse.number]).inserted {
                    verses.append(BiblePassage.Verse(chapter: chapterNumber, number: verse.number, text: verse.text))
                }
            }
        }
        return BiblePassage(reference: reference, translationName: name, translationAbbreviation: abbreviation,
                            language: language, verses: verses)
    }
}
