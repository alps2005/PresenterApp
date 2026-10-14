import Foundation

/// An order to play a presentation's groups in, like ProPresenter's arrangements: "V1 C V2 C B C C".
/// A group is every slide with the same label, in slide order. Repeating a group plays its slides again
/// without duplicating them.
public struct Arrangement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Group labels in play order. Repeats are allowed; labels with no slides are skipped.
    public var groups: [String]

    public init(id: UUID = UUID(), name: String, groups: [String]) {
        self.id = id
        self.name = name
        self.groups = groups
    }
}

/// One slot in a presentation's play order. The same slide can play more than once in an arrangement;
/// `occurrence` tells the repeats apart (0 for the first time it plays).
public struct ArrangedSlide: Hashable, Sendable {
    public let slideID: UUID
    public let occurrence: Int
}

extension PresentationDocument {
    /// Distinct group labels in the order they first appear.
    public var groupNames: [String] {
        var names: [String] = []
        for slide in slides {
            if let label = slide.label, !names.contains(label) { names.append(label) }
        }
        return names
    }

    public func slides(inGroup name: String) -> [SlideDocument] {
        slides.filter { $0.label == name }
    }

    public var activeArrangement: Arrangement? {
        guard let activeArrangementID else { return nil }
        return arrangements.first { $0.id == activeArrangementID }
    }

    /// The order slides play in: the active arrangement expanded into slides, else every slide in order.
    public var arrangedSlides: [ArrangedSlide] {
        let ids: [UUID]
        if let arrangement = activeArrangement, !arrangement.groups.isEmpty {
            ids = arrangement.groups.flatMap { slides(inGroup: $0).map(\.id) }
        } else {
            ids = slides.map(\.id)
        }
        var seen: [UUID: Int] = [:]
        return ids.map { id in
            let occurrence = seen[id, default: 0]
            seen[id] = occurrence + 1
            return ArrangedSlide(slideID: id, occurrence: occurrence)
        }
    }

    /// The presentation as text for Reflow, in New Song format: a section name when the label changes,
    /// each slide's words, and a blank line between slides. Slides without words appear as "[Blank]".
    public var reflowText: String {
        var parts: [String] = []
        var currentLabel: String?
        for slide in slides {
            var lines: [String] = []
            if let label = slide.label, label != currentLabel { lines.append(label) }
            currentLabel = slide.label ?? currentLabel
            let text = slide.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(text.isEmpty ? LyricsParser.blankSlideMarker : text)
            parts.append(lines.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    /// True when the title or any slide's words contain `query`, ignoring case and accents.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if title.range(of: query, options: options) != nil { return true }
        return slides.contains { $0.plainText.range(of: query, options: options) != nil }
    }
}
