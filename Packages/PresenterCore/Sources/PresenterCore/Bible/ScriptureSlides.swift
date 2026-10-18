import Foundation

/// Finds verses by their words, ignoring accents and case.
public enum BibleSearch {
    public struct Hit: Hashable, Sendable {
        public var book: BibleBook
        public var chapter: Int
        public var verse: Int
        public var text: String

        /// "Juan 3:16".
        public func reference(in language: BibleLanguage) -> String {
            "\(book.name(in: language)) \(chapter):\(verse)"
        }
    }

    /// Verses containing every word of `query`, in Bible order, at most `limit` of them.
    public static func search(_ query: String, in translation: BibleTranslation, limit: Int = 200) -> [Hit] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var hits: [Hit] = []
        for book in translation.books {
            guard let info = BibleBook.number(book.number) else { continue }
            for chapter in book.chapters {
                for verse in chapter.verses {
                    let text = fold(verse.text)
                    guard words.allSatisfy(text.contains) else { continue }
                    hits.append(Hit(book: info, chapter: chapter.number, verse: verse.number, text: verse.text))
                    if hits.count == limit { return hits }
                }
            }
        }
        return hits
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Turns a passage into slides: the verses as body text, and the reference as a caption on each slide, so the
/// Scripture theme places them like a reading.
public enum ScriptureSlides {
    public struct Options: Hashable, Sendable {
        /// 1 to 4.
        public var versesPerSlide: Int
        /// Small raised numbers before each verse.
        public var showsVerseNumbers: Bool
        /// The slide's reference and translation as a caption.
        public var showsReference: Bool
        /// A longer verse is split across slides at a sentence or clause break.
        public var maxCharactersPerSlide: Int

        public init(versesPerSlide: Int = 2, showsVerseNumbers: Bool = true, showsReference: Bool = true,
                    maxCharactersPerSlide: Int = 320) {
            self.versesPerSlide = versesPerSlide
            self.showsVerseNumbers = showsVerseNumbers
            self.showsReference = showsReference
            self.maxCharactersPerSlide = maxCharactersPerSlide
        }
    }

    public static func make(_ passage: BiblePassage, options: Options = Options()) -> [SlideDocument] {
        // Each verse, split into parts that fit on a slide.
        var pieces: [(verse: BiblePassage.Verse, text: String, isFirstPart: Bool)] = []
        for verse in passage.verses {
            for (index, part) in split(verse.text, max: max(80, options.maxCharactersPerSlide)).enumerated() {
                pieces.append((verse, part, index == 0))
            }
        }
        var slides: [SlideDocument] = []
        var current: [(verse: BiblePassage.Verse, text: String, isFirstPart: Bool)] = []
        let perSlide = min(max(options.versesPerSlide, 1), 4)

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let body = current.map { piece in
                options.showsVerseNumbers && piece.isFirstPart ? "\(superscript(piece.verse.number)) \(piece.text)" : piece.text
            }.joined(separator: " ")
            let numbers = range(from: first.verse, to: last.verse)
            var elements: [SlideElement] = [.text(TextElement(text: body, role: .body))]
            if options.showsReference {
                let caption = "\(passage.reference.book.name(in: passage.language)) \(numbers) · \(passage.translationAbbreviation)"
                elements.append(.text(TextElement(text: caption, role: .caption)))
            }
            // No group label: labels are for song sections, and would offer arrangements.
            slides.append(SlideDocument(elements: elements))
            current = []
        }

        for piece in pieces {
            let length = current.reduce(0) { $0 + $1.text.count } + piece.text.count
            let verses = Set(current.map { [$0.verse.chapter, $0.verse.number] }).union([[piece.verse.chapter, piece.verse.number]])
            // A new slide for the next verse once this one is full, and for every part of a split verse.
            if !current.isEmpty, verses.count > perSlide || length > options.maxCharactersPerSlide || !piece.isFirstPart {
                flush()
            }
            current.append(piece)
        }
        flush()
        return slides
    }

    /// "3:16", "3:16-17", "3:36–4:1".
    private static func range(from first: BiblePassage.Verse, to last: BiblePassage.Verse) -> String {
        if first.chapter == last.chapter {
            return first.number == last.number ? "\(first.chapter):\(first.number)" : "\(first.chapter):\(first.number)-\(last.number)"
        }
        return "\(first.chapter):\(first.number)–\(last.chapter):\(last.number)"
    }

    /// "16" → "¹⁶".
    static func superscript(_ number: Int) -> String {
        let digits: [Character] = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    /// Splits text longer than `max` at the sentence, clause or word break nearest the middle, as often as needed.
    static func split(_ text: String, max: Int) -> [String] {
        guard text.count > max else { return [text] }
        let characters = Array(text)
        let middle = characters.count / 2
        var best: Int?
        for marks in [[".", "!", "?", ";", ":"], [","], [" "]] {
            let candidates = characters.indices.filter { index in
                marks.contains(String(characters[index])) && index > 0 && index < characters.count - 1
            }
            if let nearest = candidates.min(by: { abs($0 - middle) < abs($1 - middle) }),
               abs(nearest - middle) < characters.count / 3 || marks == [" "] {
                best = nearest
                break
            }
        }
        guard let cut = best else { return [text] }
        let head = String(characters[...cut]).trimmingCharacters(in: .whitespaces)
        let tail = String(characters[(cut + 1)...]).trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !tail.isEmpty else { return [text] }
        return split(head, max: max) + split(tail, max: max)
    }
}
