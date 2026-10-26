import Foundation

/// Reads ProPresenter 7 presentations (.pro): its songs' sections (groups), slides, singing order (the selected
/// arrangement) and CCLI details. A .pro file is Protocol Buffers; the field numbers are from the openly documented
/// ProPresenter 7 schema (github.com/greyshirtguy/ProPresenter7-Proto, MIT licence), version 7.16.2. Only the
/// fields a song needs are read; slides' formatting, media and cues are left out.
enum ProPresenterParser {
    private enum Field {
        // Presentation
        static let name = 3
        static let selectedArrangement = 10
        static let arrangements = 11
        static let cueGroups = 12
        static let cues = 13
        static let ccli = 14
        // Arrangement
        static let arrangementID = 1
        static let arrangementGroups = 3
        // CueGroup → Group
        static let group = 1
        static let groupCueIDs = 2
        static let groupID = 1
        static let groupName = 2
        // Cue → Action → SlideType → PresentationSlide → Slide → Element → Graphics.Element → Text
        static let cueID = 1
        static let actions = 10
        static let actionType = 9
        static let actionSlide = 23
        static let slidePresentation = 2
        static let baseSlide = 1
        static let elements = 1
        static let element = 1
        static let text = 13
        static let rtf = 5
        // UUID
        static let uuidString = 1
        // CCLI
        static let author = 1
        static let songTitle = 3
        static let publisher = 4
        static let copyrightYear = 5
        static let songNumber = 6
    }

    /// The slide action's type (ACTION_TYPE_PRESENTATION_SLIDE).
    private static let slideActionType: UInt64 = 11

    /// Whether the file is a ProPresenter presentation (Protocol Buffers with slides or groups), words or not.
    static func isPresentation(_ data: Data) -> Bool {
        guard let presentation = try? ProtobufMessage(data) else { return false }
        return !presentation.messages(Field.cues).isEmpty || !presentation.messages(Field.cueGroups).isEmpty
    }

    /// The song in the file, or nil when it isn't a ProPresenter presentation with words on its slides.
    static func parse(_ data: Data) -> ImportedSong? {
        guard let presentation = try? ProtobufMessage(data) else { return nil }

        // Each cue's words, by its ID, in slide order.
        var words: [String: [String]] = [:]
        var cueOrder: [String] = []
        for cue in presentation.messages(Field.cues) {
            guard let id = uuid(cue.message(Field.cueID)) else { continue }
            cueOrder.append(id)
            if let lines = lines(of: cue), !lines.isEmpty { words[id] = lines }
        }
        guard !words.isEmpty else { return nil }

        // Sections from the groups, each group's name made unique ("Chorus", "Chorus" → "Chorus 1", "Chorus 2").
        let groups = presentation.messages(Field.cueGroups).map { cueGroup in
            let group = cueGroup.message(Field.group)
            return (id: uuid(group?.message(Field.groupID)),
                    name: group?.string(Field.groupName)?.trimmingCharacters(in: .whitespaces) ?? "",
                    cueIDs: cueGroup.messages(Field.groupCueIDs).compactMap { uuid($0) })
        }
        var nameCounts: [String: Int] = [:]
        for group in groups where !group.name.isEmpty { nameCounts[group.name, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var labels: [String: String] = [:]
        var sections: [ImportedSong.Section] = []
        var grouped: Set<String> = []
        for group in groups {
            var label: String? = group.name.isEmpty ? nil : group.name
            if let name = label, nameCounts[name, default: 0] > 1 {
                seen[name, default: 0] += 1
                label = "\(name) \(seen[name]!)"
            }
            if let id = group.id, let label { labels[id] = label }
            grouped.formUnion(group.cueIDs)
            let slides = group.cueIDs.compactMap { words[$0] }
            if !slides.isEmpty { sections.append(ImportedSong.Section(label: label, slides: slides)) }
        }
        // Slides in no group, in slide order.
        let loose = cueOrder.filter { !grouped.contains($0) }.compactMap { words[$0] }
        if !loose.isEmpty { sections.append(ImportedSong.Section(label: nil, slides: loose)) }

        // The selected arrangement (or the only one) is the singing order.
        let arrangements = presentation.messages(Field.arrangements)
        let selectedID = uuid(presentation.message(Field.selectedArrangement))
        let arrangement = arrangements.first { uuid($0.message(Field.arrangementID)) == selectedID }
            ?? (arrangements.count == 1 ? arrangements.first : nil)
        let order = arrangement?.messages(Field.arrangementGroups).compactMap { uuid($0).flatMap { labels[$0] } } ?? []

        var info = SongInfo()
        var title = presentation.string(Field.name) ?? ""
        if let ccli = presentation.message(Field.ccli) {
            info.authors = SongInfo.authors(from: ccli.string(Field.author) ?? "")
            let year = ccli.varint(Field.copyrightYear).flatMap { $0 > 0 ? String($0) : nil }
            let publisher = ccli.string(Field.publisher)?.trimmingCharacters(in: .whitespaces)
            info.copyright = SongInfo.copyright(from: [year, publisher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
            if let number = ccli.varint(Field.songNumber), number > 0 { info.ccliNumber = String(number) }
            if title.isEmpty { title = ccli.string(Field.songTitle) ?? "" }
        }
        return ImportedSong(title: title, info: info, sections: sections, order: order)
    }

    private static func uuid(_ message: ProtobufMessage?) -> String? {
        message?.string(Field.uuidString)?.uppercased()
    }

    /// The words of a cue's slide: its first text element with any, one line per line. Further text elements hold
    /// translations.
    private static func lines(of cue: ProtobufMessage) -> [String]? {
        for action in cue.messages(Field.actions) {
            if let type = action.varint(Field.actionType), type != slideActionType { continue }
            guard let slide = action.message(Field.actionSlide)?.message(Field.slidePresentation)?.message(Field.baseSlide)
            else { continue }
            for element in slide.messages(Field.elements) {
                guard let rtf = element.message(Field.element)?.message(Field.text)?.bytes(Field.rtf) else { continue }
                let lines = RTFText.plainText(rtf).components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if !lines.isEmpty { return lines }
            }
        }
        return nil
    }
}
