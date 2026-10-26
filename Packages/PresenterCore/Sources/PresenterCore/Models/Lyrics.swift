import Foundation

/// The kind of song section a slide's group label names, for colouring it in the operator views.
public enum SongSectionKind: Sendable, CaseIterable {
    case verse
    case preChorus
    case chorus
    case bridge
    case tag
    case intro
    case ending
    case interlude
    case other

    /// Recognises English and Spanish section names: "Verse 2", "Coro", "Pre-Chorus", "Puente"…
    public init(label: String) {
        let word = label.lowercased().replacingOccurrences(of: #"[\s\d:]+$"#, with: "", options: .regularExpression)
        switch word {
        case "verse", "verso", "estrofa": self = .verse
        case "pre-chorus", "prechorus", "pre chorus", "pre-coro", "precoro", "pre coro": self = .preChorus
        case "chorus", "coro", "refrain", "estribillo": self = .chorus
        case "bridge", "puente": self = .bridge
        case "tag": self = .tag
        case "intro": self = .intro
        case "ending", "outro", "final": self = .ending
        case "interlude", "interludio", "instrumental": self = .interlude
        default: self = .other
        }
    }

    /// The section a key jumps to while operating, as in ProPresenter: V verse, C chorus, P pre-chorus, B bridge,
    /// T tag, I intro, E ending, N interlude. Nil for any other key.
    public init?(hotkey: Character) {
        switch hotkey.lowercased() {
        case "v": self = .verse
        case "c": self = .chorus
        case "p": self = .preChorus
        case "b": self = .bridge
        case "t": self = .tag
        case "i": self = .intro
        case "e": self = .ending
        case "n": self = .interlude
        default: return nil
        }
    }

    /// The number a label ends with ("Verse 2" → 2), or nil when it has none.
    public static func number(inLabel label: String) -> Int? {
        guard let range = label.range(of: #"\d+\s*:?\s*$"#, options: .regularExpression) else { return nil }
        return Int(label[range].filter(\.isNumber))
    }
}

/// Turns pasted lyrics into slides, the way songs are usually typed out:
/// - a blank line starts a new slide;
/// - a line that is only a section name ("Verse 1", "[Chorus]", "CORO:", "Puente") isn't shown on a slide;
///   it labels the slides that follow it until the next section name.
public enum LyricsParser {
    /// Marks a slide without words in Reflow text, so it isn't lost.
    public static let blankSlideMarker = "[Blank]"

    private static let sectionPattern = try! NSRegularExpression(
        pattern: #"^(verse|verso|estrofa|chorus|coro|refrain|estribillo|pre[- ]?chorus|pre[- ]?coro|bridge|puente|tag|intro|outro|final|ending|interlude|interludio|instrumental)(\s*\d+)?$"#,
        options: [.caseInsensitive]
    )

    /// `maxLinesPerSlide` splits long stanzas into slides of at most that many lines; nil keeps whole stanzas.
    public static func slides(from lyrics: String, maxLinesPerSlide: Int? = nil) -> [SlideDocument] {
        var slides: [SlideDocument] = []
        var label: String?
        var stanza: [String] = []

        func flush() {
            guard !stanza.isEmpty else { return }
            let size = max(maxLinesPerSlide ?? stanza.count, 1)
            for start in stride(from: 0, to: stanza.count, by: size) {
                let lines = stanza[start..<min(start + size, stanza.count)]
                var slide = SlideDocument.text(lines.joined(separator: "\n"))
                slide.label = label
                slides.append(slide)
            }
            stanza.removeAll()
        }

        let normalized = lyrics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.caseInsensitiveCompare(blankSlideMarker) == .orderedSame {
                flush()
                var slide = SlideDocument.text("")
                slide.label = label
                slides.append(slide)
            } else if let name = sectionLabel(line) {
                flush()
                label = name
            } else {
                stanza.append(line)
            }
        }
        flush()
        return slides
    }

    /// The tidied section name if the line is only a section name ("[chorus 2]:" → "Chorus 2"), else nil.
    public static func sectionLabel(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(":") { text.removeLast() }
        if (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")")) {
            text = String(text.dropFirst().dropLast())
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(text.startIndex..., in: text)
        guard sectionPattern.firstMatch(in: text, range: range) != nil else { return nil }
        return text.lowercased().capitalized
    }
}
