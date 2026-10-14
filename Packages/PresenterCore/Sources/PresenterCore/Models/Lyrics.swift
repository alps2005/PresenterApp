import Foundation

/// The kind of song section a slide's group label names, for colouring it in the operator views.
public enum SongSectionKind: Sendable, CaseIterable {
    case verse
    case preChorus
    case chorus
    case bridge
    case other

    /// Recognises English and Spanish section names: "Verse 2", "Coro", "Pre-Chorus", "Puente"…
    public init(label: String) {
        let word = label.lowercased().replacingOccurrences(of: #"[\s\d:]+$"#, with: "", options: .regularExpression)
        switch word {
        case "verse", "verso", "estrofa": self = .verse
        case "pre-chorus", "prechorus", "pre chorus", "pre-coro", "precoro", "pre coro": self = .preChorus
        case "chorus", "coro", "refrain", "estribillo": self = .chorus
        case "bridge", "puente": self = .bridge
        default: self = .other
        }
    }
}

/// Turns pasted lyrics into slides, the way songs are usually typed out:
/// - a blank line starts a new slide;
/// - a line that is only a section name ("Verse 1", "[Chorus]", "CORO:", "Puente") isn't shown on a slide;
///   it labels the slides that follow it until the next section name.
public enum LyricsParser {
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
