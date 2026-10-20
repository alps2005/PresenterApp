import Foundation

/// Reads ChordPro (chordpro.org): lyrics with `[G]` chords inline and `{directive: value}` lines. Chords, tabs, grids
/// and `#` comments are dropped. Sections come from `{start_of_verse: Verse 1}`-style environments, `{comment: Chorus}`
/// lines, or a section name on a line of its own; `{chorus}` sings the last chorus again. A blank line starts a new
/// slide.
enum ChordProParser {
    /// True for text with a ChordPro title, section or chord-heavy look: `{title:`, `{start_of_`/`{so`, or `[G]` chords.
    static func looksLikeChordPro(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("{title:") || lowered.contains("{t:") || lowered.contains("{start_of_")
            || lowered.range(of: #"\{so[cvb]\b"#, options: .regularExpression) != nil {
            return true
        }
        return text.range(of: #"\[[A-G][#b]?(m|maj|min|sus|dim|aug|add)?\d*(/[A-G][#b]?)?\]"#, options: .regularExpression) != nil
    }

    static func parse(_ text: String) -> ImportedSong {
        var builder = Builder()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if builder.skipping {
                if let (name, _) = directive(line), ["end_of_tab", "eot", "end_of_grid", "eog"].contains(name) {
                    builder.skipping = false
                }
                continue
            }
            if line.hasPrefix("#") { continue }
            if let (name, value) = directive(line) {
                builder.apply(name, value)
                continue
            }
            let words = stripChords(line)
            if words.isEmpty {
                builder.breakSlide()
            } else if let label = LyricsParser.sectionLabel(words) {
                builder.startSection(label)
            } else {
                builder.addLine(words)
            }
        }
        return builder.finish()
    }

    /// `{name: value}` or `{name}` → (lowercased name, value). Nil for anything else.
    static func directive(_ line: String) -> (String, String)? {
        guard line.hasPrefix("{"), line.hasSuffix("}") else { return nil }
        let body = line.dropFirst().dropLast()
        guard let separator = body.firstIndex(where: { $0 == ":" || $0 == " " }) else {
            return (body.trimmingCharacters(in: .whitespaces).lowercased(), "")
        }
        let name = body[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
        let value = body[body.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return (name, value)
    }

    /// The words without `[chord]` marks, spaces tidied.
    static func stripChords(_ line: String) -> String {
        line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Builder {
        var title = ""
        var info = SongInfo()
        var sections: [ImportedSong.Section] = []
        var order: [String] = []
        /// Inside a tab or grid, whose lines aren't lyrics.
        var skipping = false
        /// The verses and choruses without a name so far, to number them.
        private var unnamedVerses = 0
        private var lastChorus: String?
        /// Whether the file repeats a section with `{chorus}`, so the order is worth keeping.
        private var repeats = false

        mutating func apply(_ name: String, _ value: String) {
            let value = name.hasPrefix("start_of_") || ["sov", "soc", "sob", "sop"].contains(name) ? sectionName(value) : value
            switch name {
            case "title", "t":
                if title.isEmpty { title = value }
            case "artist", "composer", "lyricist", "author":
                for author in SongInfo.authors(from: value) where !info.authors.contains(author) { info.authors.append(author) }
            case "copyright", "(c)":
                info.copyright = SongInfo.copyright(from: value)
            case "ccli", "ccli_song", "ccli_number", "ccli_song_number":
                info.ccliNumber = SongInfo.ccliNumber(from: value)
            case "start_of_verse", "sov":
                if value.isEmpty {
                    unnamedVerses += 1
                    startSection("Verse \(unnamedVerses)")
                } else {
                    startSection(value)
                }
            case "start_of_chorus", "soc":
                startSection(value.isEmpty ? "Chorus" : value)
            case "start_of_bridge", "sob":
                startSection(value.isEmpty ? "Bridge" : value)
            case "start_of_part", "sop":
                startSection(value.isEmpty ? nil : value)
            case "end_of_verse", "eov", "end_of_chorus", "eoc", "end_of_bridge", "eob", "end_of_part", "eop":
                breakSlide()
            case "start_of_tab", "sot", "start_of_grid", "sog":
                skipping = true
            case "chorus":
                // Sing the last chorus again.
                if let chorus = lastChorus {
                    order.append(chorus)
                    repeats = true
                }
            case "comment", "c", "comment_italic", "ci", "comment_box", "cb", "highlight":
                if let label = LyricsParser.sectionLabel(value) { startSection(label) }
            default:
                break
            }
        }

        /// ChordPro 6 names a section with an attribute: `{start_of_verse label="Verse 1"}`.
        private func sectionName(_ value: String) -> String {
            guard value.hasPrefix("label=") else { return value }
            return value.dropFirst("label=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }

        mutating func startSection(_ label: String?) {
            sections.append(ImportedSong.Section(label: label, slides: [[]]))
            if let label {
                order.append(label)
                if SongSectionKind(label: label) == .chorus { lastChorus = label }
            }
        }

        mutating func addLine(_ line: String) {
            if sections.isEmpty { sections.append(ImportedSong.Section(label: nil, slides: [[]])) }
            let last = sections.count - 1
            if sections[last].slides.isEmpty { sections[last].slides.append([]) }
            sections[last].slides[sections[last].slides.count - 1].append(line)
        }

        mutating func breakSlide() {
            guard let last = sections.indices.last, sections[last].slides.last?.isEmpty == false else { return }
            sections[last].slides.append([])
        }

        func finish() -> ImportedSong {
            var song = ImportedSong(title: title, info: info, sections: sections, order: repeats ? order : [])
            song.numberRepeatedLabels()
            return song
        }
    }
}
