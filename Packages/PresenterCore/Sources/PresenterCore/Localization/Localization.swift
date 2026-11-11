import Foundation

/// A language the apps are written in. English is the language the code is written in; the others are tables.
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case spanish = "es"

    /// The language for a list of preferred language codes ("es-MX", "en-US"…), as macOS and Windows give them:
    /// the first one the apps are written in, else English.
    public static func preferred(from codes: [String]) -> AppLanguage {
        for code in codes {
            let base = code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if let language = AppLanguage(rawValue: base) { return language }
        }
        return .english
    }
}

/// The engine's words in the operator's language: messages, undo names and the names new things get. Both apps set
/// `language` once at launch (the Mac app from its own localization, the Windows app through the bridge), so the
/// engine's words match the rest of the screen.
///
/// The tables are plain Swift, not a String Catalog, so they work on Windows too. The English text is the key; a
/// missing translation shows the English.
public enum Localization {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: AppLanguage = .english

    public static var language: AppLanguage {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    /// `english` in the current language. `{0}`, `{1}`… are filled with `arguments`, in order, after translating,
    /// so a translation can put them where its grammar needs them.
    public static func text(_ english: String, _ arguments: String...) -> String {
        text(english, arguments: arguments, in: language)
    }

    public static func text(_ english: String, arguments: [String] = [], in language: AppLanguage) -> String {
        var result = table(for: language)[english] ?? english
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        return result
    }

    /// Every translation for a language, keyed by its English. Empty for English.
    public static func table(for language: AppLanguage) -> [String: String] {
        switch language {
        case .english: [:]
        case .spanish: SpanishText.table
        }
    }

    /// The `{n}` placeholders in a text, for checking that a translation keeps them all.
    public static func placeholders(in text: String) -> Set<String> {
        var found: Set<String> = []
        var rest = text[...]
        while let open = rest.firstIndex(of: "{") {
            let after = rest[rest.index(after: open)...]
            guard let close = after.firstIndex(of: "}") else { break }
            let inside = after[..<close]
            if !inside.isEmpty, inside.allSatisfy(\.isNumber) { found.insert("{\(inside)}") }
            rest = after[after.index(after: close)...]
        }
        return found
    }
}
