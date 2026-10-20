import Foundation

/// The language a Bible translation, and the names of its books, are in.
public enum BibleLanguage: String, Codable, Hashable, Sendable, CaseIterable {
    case english = "en"
    case spanish = "es"
}

/// One of the 66 books of the Protestant canon, in order, with its names in English and Spanish.
public struct BibleBook: Hashable, Sendable, Identifiable {
    /// 1 (Genesis) to 66 (Revelation), as Zefania files number them.
    public let number: Int
    /// The OSIS book code, as OSIS files name them (e.g. "Gen", "1Cor").
    public let osis: String
    public let english: String
    public let spanish: String
    /// Short forms people type, besides any unique start of either name.
    let abbreviations: [String]

    public var id: Int { number }

    public func name(in language: BibleLanguage) -> String {
        language == .spanish ? spanish : english
    }

    public var isNewTestament: Bool { number >= 40 }
}

extension BibleBook {
    /// Every book, in canonical order.
    public static let all: [BibleBook] = [
        BibleBook(number: 1, osis: "Gen", english: "Genesis", spanish: "Génesis", abbreviations: ["gn", "ge"]),
        BibleBook(number: 2, osis: "Exod", english: "Exodus", spanish: "Éxodo", abbreviations: ["ex", "exo"]),
        BibleBook(number: 3, osis: "Lev", english: "Leviticus", spanish: "Levítico", abbreviations: ["lv"]),
        BibleBook(number: 4, osis: "Num", english: "Numbers", spanish: "Números", abbreviations: ["nm", "nb"]),
        BibleBook(number: 5, osis: "Deut", english: "Deuteronomy", spanish: "Deuteronomio", abbreviations: ["dt"]),
        BibleBook(number: 6, osis: "Josh", english: "Joshua", spanish: "Josué", abbreviations: ["jos"]),
        BibleBook(number: 7, osis: "Judg", english: "Judges", spanish: "Jueces", abbreviations: ["jue", "jdg", "jg", "jc"]),
        BibleBook(number: 8, osis: "Ruth", english: "Ruth", spanish: "Rut", abbreviations: ["rt", "rth"]),
        BibleBook(number: 9, osis: "1Sam", english: "1 Samuel", spanish: "1 Samuel", abbreviations: ["1s", "1sa", "1sm"]),
        BibleBook(number: 10, osis: "2Sam", english: "2 Samuel", spanish: "2 Samuel", abbreviations: ["2s", "2sa", "2sm"]),
        BibleBook(number: 11, osis: "1Kgs", english: "1 Kings", spanish: "1 Reyes", abbreviations: ["1r", "1re", "1k", "1ki", "1kgs"]),
        BibleBook(number: 12, osis: "2Kgs", english: "2 Kings", spanish: "2 Reyes", abbreviations: ["2r", "2re", "2k", "2ki", "2kgs"]),
        BibleBook(number: 13, osis: "1Chr", english: "1 Chronicles", spanish: "1 Crónicas", abbreviations: ["1cr", "1ch", "1chr"]),
        BibleBook(number: 14, osis: "2Chr", english: "2 Chronicles", spanish: "2 Crónicas", abbreviations: ["2cr", "2ch", "2chr"]),
        BibleBook(number: 15, osis: "Ezra", english: "Ezra", spanish: "Esdras", abbreviations: ["esd", "ezr"]),
        BibleBook(number: 16, osis: "Neh", english: "Nehemiah", spanish: "Nehemías", abbreviations: ["ne"]),
        BibleBook(number: 17, osis: "Esth", english: "Esther", spanish: "Ester", abbreviations: ["est"]),
        BibleBook(number: 18, osis: "Job", english: "Job", spanish: "Job", abbreviations: ["jb"]),
        BibleBook(number: 19, osis: "Ps", english: "Psalms", spanish: "Salmos", abbreviations: ["sal", "sl", "ps", "psa", "pss"]),
        BibleBook(number: 20, osis: "Prov", english: "Proverbs", spanish: "Proverbios", abbreviations: ["pr", "prv"]),
        BibleBook(number: 21, osis: "Eccl", english: "Ecclesiastes", spanish: "Eclesiastés", abbreviations: ["ec", "ecc", "qoh"]),
        BibleBook(number: 22, osis: "Song", english: "Song of Songs", spanish: "Cantares",
                  abbreviations: ["cnt", "cant", "cantar", "sos", "sg", "songofsolomon", "cantardeloscantares"]),
        BibleBook(number: 23, osis: "Isa", english: "Isaiah", spanish: "Isaías", abbreviations: ["is"]),
        BibleBook(number: 24, osis: "Jer", english: "Jeremiah", spanish: "Jeremías", abbreviations: ["jr"]),
        BibleBook(number: 25, osis: "Lam", english: "Lamentations", spanish: "Lamentaciones", abbreviations: ["lm"]),
        BibleBook(number: 26, osis: "Ezek", english: "Ezekiel", spanish: "Ezequiel", abbreviations: ["ez", "eze", "ezk"]),
        BibleBook(number: 27, osis: "Dan", english: "Daniel", spanish: "Daniel", abbreviations: ["dn"]),
        BibleBook(number: 28, osis: "Hos", english: "Hosea", spanish: "Oseas", abbreviations: ["os", "ho"]),
        BibleBook(number: 29, osis: "Joel", english: "Joel", spanish: "Joel", abbreviations: ["jl"]),
        BibleBook(number: 30, osis: "Amos", english: "Amos", spanish: "Amós", abbreviations: ["am"]),
        BibleBook(number: 31, osis: "Obad", english: "Obadiah", spanish: "Abdías", abbreviations: ["abd", "ob"]),
        BibleBook(number: 32, osis: "Jonah", english: "Jonah", spanish: "Jonás", abbreviations: ["jon", "jnh"]),
        BibleBook(number: 33, osis: "Mic", english: "Micah", spanish: "Miqueas", abbreviations: ["mi", "mq"]),
        BibleBook(number: 34, osis: "Nah", english: "Nahum", spanish: "Nahúm", abbreviations: ["na"]),
        BibleBook(number: 35, osis: "Hab", english: "Habakkuk", spanish: "Habacuc", abbreviations: ["hb"]),
        BibleBook(number: 36, osis: "Zeph", english: "Zephaniah", spanish: "Sofonías", abbreviations: ["sof", "zep"]),
        BibleBook(number: 37, osis: "Hag", english: "Haggai", spanish: "Hageo", abbreviations: ["hg"]),
        BibleBook(number: 38, osis: "Zech", english: "Zechariah", spanish: "Zacarías", abbreviations: ["zac", "zec"]),
        BibleBook(number: 39, osis: "Mal", english: "Malachi", spanish: "Malaquías", abbreviations: ["ml"]),
        BibleBook(number: 40, osis: "Matt", english: "Matthew", spanish: "Mateo", abbreviations: ["mt", "mat"]),
        BibleBook(number: 41, osis: "Mark", english: "Mark", spanish: "Marcos", abbreviations: ["mr", "mc", "mk", "mrk"]),
        BibleBook(number: 42, osis: "Luke", english: "Luke", spanish: "Lucas", abbreviations: ["lc", "lk", "luk"]),
        BibleBook(number: 43, osis: "John", english: "John", spanish: "Juan", abbreviations: ["jn", "jhn"]),
        BibleBook(number: 44, osis: "Acts", english: "Acts", spanish: "Hechos", abbreviations: ["hch", "hc", "ac"]),
        BibleBook(number: 45, osis: "Rom", english: "Romans", spanish: "Romanos", abbreviations: ["ro", "rm"]),
        BibleBook(number: 46, osis: "1Cor", english: "1 Corinthians", spanish: "1 Corintios", abbreviations: ["1co", "1cor"]),
        BibleBook(number: 47, osis: "2Cor", english: "2 Corinthians", spanish: "2 Corintios", abbreviations: ["2co", "2cor"]),
        BibleBook(number: 48, osis: "Gal", english: "Galatians", spanish: "Gálatas", abbreviations: ["ga"]),
        BibleBook(number: 49, osis: "Eph", english: "Ephesians", spanish: "Efesios", abbreviations: ["ef"]),
        BibleBook(number: 50, osis: "Phil", english: "Philippians", spanish: "Filipenses", abbreviations: ["fil", "flp", "php"]),
        BibleBook(number: 51, osis: "Col", english: "Colossians", spanish: "Colosenses", abbreviations: ["cl"]),
        BibleBook(number: 52, osis: "1Thess", english: "1 Thessalonians", spanish: "1 Tesalonicenses", abbreviations: ["1ts", "1te", "1th"]),
        BibleBook(number: 53, osis: "2Thess", english: "2 Thessalonians", spanish: "2 Tesalonicenses", abbreviations: ["2ts", "2te", "2th"]),
        BibleBook(number: 54, osis: "1Tim", english: "1 Timothy", spanish: "1 Timoteo", abbreviations: ["1ti", "1tm"]),
        BibleBook(number: 55, osis: "2Tim", english: "2 Timothy", spanish: "2 Timoteo", abbreviations: ["2ti", "2tm"]),
        BibleBook(number: 56, osis: "Titus", english: "Titus", spanish: "Tito", abbreviations: ["tit", "tt"]),
        BibleBook(number: 57, osis: "Phlm", english: "Philemon", spanish: "Filemón", abbreviations: ["flm", "phm", "phlm"]),
        BibleBook(number: 58, osis: "Heb", english: "Hebrews", spanish: "Hebreos", abbreviations: ["he"]),
        BibleBook(number: 59, osis: "Jas", english: "James", spanish: "Santiago", abbreviations: ["stg", "sant", "jas", "jm", "st"]),
        BibleBook(number: 60, osis: "1Pet", english: "1 Peter", spanish: "1 Pedro", abbreviations: ["1p", "1pe", "1pt", "1pd"]),
        BibleBook(number: 61, osis: "2Pet", english: "2 Peter", spanish: "2 Pedro", abbreviations: ["2p", "2pe", "2pt", "2pd"]),
        BibleBook(number: 62, osis: "1John", english: "1 John", spanish: "1 Juan", abbreviations: ["1jn", "1jo", "1jhn"]),
        BibleBook(number: 63, osis: "2John", english: "2 John", spanish: "2 Juan", abbreviations: ["2jn", "2jo", "2jhn"]),
        BibleBook(number: 64, osis: "3John", english: "3 John", spanish: "3 Juan", abbreviations: ["3jn", "3jo", "3jhn"]),
        BibleBook(number: 65, osis: "Jude", english: "Jude", spanish: "Judas", abbreviations: ["jud", "jd"]),
        BibleBook(number: 66, osis: "Rev", english: "Revelation", spanish: "Apocalipsis", abbreviations: ["ap", "apoc", "re", "rv", "revelations"]),
    ]

    public static func number(_ number: Int) -> BibleBook? {
        all.indices.contains(number - 1) ? all[number - 1] : nil
    }

    public static func osis(_ code: String) -> BibleBook? {
        all.first { $0.osis.caseInsensitiveCompare(code) == .orderedSame }
    }

    /// The Paratext (USFM) book codes USFX and USX files use, in canonical order.
    static let usfmCodes = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR", "NEH",
        "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON",
        "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
        "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN",
        "JUD", "REV",
    ]

    /// The book with this Paratext code ("JHN"). Nil for books outside the 66, such as the deuterocanon ("TOB").
    public static func usfm(_ code: String) -> BibleBook? {
        usfmCodes.firstIndex(of: code.uppercased()).flatMap { number($0 + 1) }
    }
}

/// Finds a book from what someone typed, in English or Spanish, ignoring accents, case, dots and spaces.
public enum BibleBookLookup {
    public enum Match: Equatable, Sendable {
        case book(BibleBook)
        /// Several books start that way; the closest few, to suggest.
        case ambiguous([BibleBook])
        case none
    }

    /// Exact abbreviation first (so "jn" is John and "jon" Jonah), then a full name, then a unique start of a name.
    public static func match(_ typed: String) -> Match {
        let key = normalized(typed)
        guard !key.isEmpty else { return .none }
        if let book = abbreviationTable[key] ?? nameTable[key] { return .book(book) }
        let starts = BibleBook.all.filter { book in
            names(of: book).contains { $0.hasPrefix(key) }
        }
        switch starts.count {
        case 0: return .none
        case 1: return .book(starts[0])
        default: return .ambiguous(Array(starts.prefix(6)))
        }
    }

    /// Lowercased without accents, dots or spaces, with a leading ordinal written as a digit:
    /// "1ra de Juan", "Primera Juan", "I Juan" and "1 Juan" all become "1juan".
    static func normalized(_ text: String) -> String {
        var words = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if let first = words.first, let digit = ordinals[first], words.count > 1 {
            words[0] = digit
            if words.count > 2, words[1] == "de" || words[1] == "of" { words.remove(at: 1) }
        }
        return words.joined()
    }

    private static let ordinals: [String: String] = [
        "1": "1", "i": "1", "1st": "1", "first": "1", "1ra": "1", "1ro": "1", "1a": "1", "1o": "1", "primera": "1", "primero": "1", "primer": "1",
        "2": "2", "ii": "2", "2nd": "2", "second": "2", "2da": "2", "2do": "2", "2a": "2", "2o": "2", "segunda": "2", "segundo": "2",
        "3": "3", "iii": "3", "3rd": "3", "third": "3", "3ra": "3", "3ro": "3", "3a": "3", "3o": "3", "tercera": "3", "tercero": "3",
    ]

    private static func names(of book: BibleBook) -> [String] {
        [normalized(book.english), normalized(book.spanish)]
    }

    private static let nameTable: [String: BibleBook] = {
        var table: [String: BibleBook] = [:]
        for book in BibleBook.all {
            for name in names(of: book) { table[name] = book }
        }
        return table
    }()

    private static let abbreviationTable: [String: BibleBook] = {
        var table: [String: BibleBook] = [:]
        for book in BibleBook.all {
            for abbreviation in book.abbreviations { table[abbreviation] = book }
        }
        return table
    }()
}
