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
        make(passage, second: nil, options: options)
    }

    /// Where each translation sits when a passage shows in two: the first across the top, the second below it,
    /// leaving the bottom for the reference. The theme still styles the words; only their place is fixed.
    static let firstTranslationBox = TextBox(frame: NormalizedRect(x: 0.056, y: 0.06, width: 0.888, height: 0.38),
                                             verticalAlignment: .top)
    static let secondTranslationBox = TextBox(frame: NormalizedRect(x: 0.056, y: 0.46, width: 0.888, height: 0.36),
                                              verticalAlignment: .top)

    /// The passage's slides. With a `second` passage (the same reference in another Bible), each slide shows the
    /// same verses in both, one above the other; a verse the second Bible doesn't have leaves its half without it.
    public static func make(_ passage: BiblePassage, second: BiblePassage?, options: Options = Options()) -> [SlideDocument] {
        // Each half of a two-translation slide holds half as much.
        let limit = second == nil ? options.maxCharactersPerSlide : max(80, options.maxCharactersPerSlide / 2)
        let secondTexts = Dictionary(second?.verses.map { (VerseKey($0), $0.text) } ?? [], uniquingKeysWith: { first, _ in first })

        // Each verse, split into parts that fit; both translations of a verse split into the same number of parts.
        var pieces: [Piece] = []
        for verse in passage.verses {
            let other = second == nil ? nil : secondTexts[VerseKey(verse)] ?? ""
            let firstParts = split(verse.text, max: max(80, limit))
            let count = max(firstParts.count, other.map { split($0, max: max(80, limit)).count } ?? 1)
            let parts = count == firstParts.count ? firstParts : divide(verse.text, into: count)
            let otherParts = other.map { divide($0, into: count) }
            for index in parts.indices {
                pieces.append(Piece(verse: verse, text: parts[index], other: otherParts?[index], isFirstPart: index == 0))
            }
        }
        var slides: [SlideDocument] = []
        var current: [Piece] = []
        let perSlide = min(max(options.versesPerSlide, 1), 4)

        func body(_ text: (Piece) -> String?) -> String {
            current.compactMap { piece -> String? in
                guard let part = text(piece), !part.isEmpty else { return nil }
                return options.showsVerseNumbers && piece.isFirstPart ? "\(superscript(piece.verse.number)) \(part)" : part
            }.joined(separator: " ")
        }

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let numbers = range(from: first.verse, to: last.verse)
            var elements: [SlideElement]
            if let second {
                elements = [
                    .text(TextElement(text: body(\.text), role: .body, box: firstTranslationBox, overrides: [.box])),
                    .text(TextElement(text: body(\.other), role: .body, box: secondTranslationBox, overrides: [.box])),
                ]
                if options.showsReference {
                    let caption = "\(passage.reference.book.name(in: passage.language)) \(numbers) · \(passage.translationAbbreviation) / \(second.translationAbbreviation)"
                    elements.append(.text(TextElement(text: caption, role: .caption)))
                }
            } else {
                elements = [.text(TextElement(text: body(\.text), role: .body))]
                if options.showsReference {
                    let caption = "\(passage.reference.book.name(in: passage.language)) \(numbers) · \(passage.translationAbbreviation)"
                    elements.append(.text(TextElement(text: caption, role: .caption)))
                }
            }
            // No group label: labels are for song sections, and would offer arrangements.
            slides.append(SlideDocument(elements: elements))
            current = []
        }

        for piece in pieces {
            let length = max(current.reduce(0) { $0 + $1.text.count } + piece.text.count,
                             current.reduce(0) { $0 + ($1.other?.count ?? 0) } + (piece.other?.count ?? 0))
            let verses = Set(current.map { VerseKey($0.verse) }).union([VerseKey(piece.verse)])
            // A new slide for the next verse once this one is full, and for every part of a split verse.
            if !current.isEmpty, verses.count > perSlide || length > limit || !piece.isFirstPart {
                flush()
            }
            current.append(piece)
        }
        flush()
        return slides
    }

    private struct VerseKey: Hashable {
        let chapter: Int
        let number: Int
        init(_ verse: BiblePassage.Verse) {
            chapter = verse.chapter
            number = verse.number
        }
    }

    /// Part of a verse, with the same part of it in the second translation, if there is one.
    private struct Piece {
        let verse: BiblePassage.Verse
        let text: String
        let other: String?
        let isFirstPart: Bool
    }

    /// Cuts text into `count` parts of about equal length, at the sentence, clause or word break nearest each cut.
    static func divide(_ text: String, into count: Int) -> [String] {
        guard count > 1 else { return [text] }
        let characters = Array(text)
        var cuts: [Int] = []
        for part in 1..<count {
            let target = characters.count * part / count
            let lower = cuts.last.map { $0 + 1 } ?? 1
            guard lower < characters.count - 1 else { break }
            let window = max(characters.count / (count * 3), 1)
            var chosen: Int?
            for marks in [[".", "!", "?", ";", ":"], [","], [" "]] {
                let candidates = (lower..<(characters.count - 1)).filter { marks.contains(String(characters[$0])) }
                if let nearest = candidates.min(by: { abs($0 - target) < abs($1 - target) }),
                   abs(nearest - target) <= window || marks == [" "] {
                    chosen = nearest
                    break
                }
            }
            if let chosen { cuts.append(chosen) }
        }
        var parts: [String] = []
        var start = 0
        for cut in cuts {
            parts.append(String(characters[start...cut]).trimmingCharacters(in: .whitespaces))
            start = cut + 1
        }
        parts.append(String(characters[start...]).trimmingCharacters(in: .whitespaces))
        // A text with too few breaks gives fewer parts; the rest stay empty so both translations keep step.
        return parts + Array(repeating: "", count: max(0, count - parts.count))
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
