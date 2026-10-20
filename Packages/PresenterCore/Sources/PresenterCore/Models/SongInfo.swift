import Foundation

/// A song's credits, as song files and SongSelect give them: who wrote it, its copyright line and its CCLI song number,
/// which churches report under their CCLI licence.
public struct SongInfo: Codable, Hashable, Sendable {
    /// Writers in the order the source lists them.
    public var authors: [String]
    /// The copyright line, without a leading "©" ("2006 sixsteps Music"), or "Public Domain".
    public var copyright: String
    /// The CCLI song number, digits only. Empty when the song isn't in CCLI's catalogue or it isn't known.
    public var ccliNumber: String

    public init(authors: [String] = [], copyright: String = "", ccliNumber: String = "") {
        self.authors = authors
        self.copyright = copyright
        self.ccliNumber = ccliNumber
    }

    /// True when nothing is filled in.
    public var isEmpty: Bool {
        authors.isEmpty && copyright.isEmpty && ccliNumber.isEmpty
    }

    /// "Chris Tomlin, John Newton", as one line.
    public var authorLine: String {
        authors.joined(separator: ", ")
    }

    /// Writers from one line of text, split at commas, semicolons, " | " and " & ", the separators song files use.
    public static func authors(from line: String) -> [String] {
        line.components(separatedBy: CharacterSet(charactersIn: ",;|&"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A copyright line tidied: no "©", "(c)" or "Copyright" in front, which the credits add back.
    public static func copyright(from line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        // Repeated, for "Copyright © 2006".
        while let prefix = ["©", "(c)", "(C)", "Copyright", "copyright"].first(where: text.hasPrefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// The digits of a CCLI number ("CCLI Song # 4768151" → "4768151").
    public static func ccliNumber(from text: String) -> String {
        String(text.filter(\.isASCII).filter(\.isNumber))
    }
}
