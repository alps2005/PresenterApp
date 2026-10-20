import Foundation

/// Reads the two files CCLI SongSelect downloads.
/// - The lyrics text (.txt): the title, then each section under its name ("Verse 1", "Chorus"), then a footer with
///   "CCLI Song #", the writers (split at "|"), the "©" line, the terms of use and "CCLI License #".
/// - SongPro (.usr), an INI file: `[S A4768151]` with `Title=`, `Author=`, `Copyright=`, `Fields=` (section names)
///   and `Words=` (each section's words), sections split by `/t` and lines by `/n`.
enum SongSelectParser {
    static func looksLikeLyricsExport(_ text: String) -> Bool {
        text.range(of: #"(?m)^\s*CCLI Song\s*#"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeSongPro(_ text: String) -> Bool {
        text.range(of: #"(?m)^\s*Words="#, options: .regularExpression) != nil
            && text.range(of: #"(?m)^\s*Fields="#, options: .regularExpression) != nil
    }

    // MARK: Lyrics text

    static func parseLyricsExport(_ text: String) -> ImportedSong {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let footerStart = lines.firstIndex { $0.range(of: #"^CCLI Song\s*#"#, options: [.regularExpression, .caseInsensitive]) != nil }
            ?? lines.endIndex
        var body = Array(lines[..<footerStart])
        var title = ""
        if let first = body.firstIndex(where: { !$0.isEmpty }) {
            title = body[first]
            body.removeSubrange(...first)
        }

        var sections: [ImportedSong.Section] = []
        for block in SongImporter.stanzas(body) {
            if let label = sectionLabel(block[0]) {
                let words = Array(block.dropFirst())
                sections.append(ImportedSong.Section(label: label, slides: words.isEmpty ? [] : [words]))
            } else if sections.isEmpty {
                sections.append(ImportedSong.Section(label: nil, slides: [block]))
            } else {
                sections[sections.count - 1].slides.append(block)
            }
        }

        var info = SongInfo()
        for line in lines[footerStart...] where !line.isEmpty {
            let lowered = line.lowercased()
            if lowered.hasPrefix("ccli song") {
                info.ccliNumber = SongInfo.ccliNumber(from: line)
            } else if lowered.hasPrefix("ccli licen") || lowered.hasPrefix("for use solely") || lowered.contains("www.ccli.com") {
                continue
            } else if line.hasPrefix("©") || lowered.hasPrefix("copyright") || lowered.hasPrefix("public domain") {
                info.copyright = SongInfo.copyright(from: line)
            } else if info.authors.isEmpty {
                info.authors = SongInfo.authors(from: line)
            }
        }
        var song = ImportedSong(title: title, info: info, sections: sections)
        song.numberRepeatedLabels()
        return song
    }

    /// A section name as SongSelect writes them, including names New Song doesn't know ("Misc 1", "Vamp").
    static func sectionLabel(_ line: String) -> String? {
        if let label = LyricsParser.sectionLabel(line) { return label }
        let extra = #"^(misc|vamp|coda|turnaround|channel|rap|spoken|refrain|chant|interlude|pre-?bridge)(\s*\d+)?$"#
        guard line.range(of: extra, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return line.lowercased().capitalized
    }

    // MARK: SongPro

    static func parseSongPro(_ text: String) -> ImportedSong {
        var values: [String: String] = [:]
        var ccliNumber = ""
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[S ") {
                ccliNumber = SongInfo.ccliNumber(from: line)
            } else if let separator = line.firstIndex(of: "=") {
                let key = line[..<separator].lowercased()
                if values[key] == nil { values[key] = String(line[line.index(after: separator)...]) }
            }
        }
        let names = (values["fields"] ?? "").components(separatedBy: "/t")
        let words = (values["words"] ?? "").components(separatedBy: "/t")
        var sections: [ImportedSong.Section] = []
        for (index, block) in words.enumerated() {
            let lines = block.components(separatedBy: "/n").map { $0.trimmingCharacters(in: .whitespaces) }
            let name = index < names.count ? names[index].trimmingCharacters(in: .whitespaces) : ""
            sections.append(ImportedSong.Section(label: name.isEmpty ? nil : name, slides: SongImporter.stanzas(lines)))
        }
        let info = SongInfo(authors: SongInfo.authors(from: values["author"] ?? ""),
                            copyright: SongInfo.copyright(from: (values["copyright"] ?? "").replacingOccurrences(of: " | ", with: ", ")),
                            ccliNumber: ccliNumber)
        var song = ImportedSong(title: values["title"] ?? "", info: info, sections: sections)
        song.numberRepeatedLabels()
        return song
    }
}
