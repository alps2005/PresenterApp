import Foundation

/// A message shown over the slides on the audience output, like ProPresenter's messages:
/// "Parent of child {Number}, please come to the nursery". `{Name}` is a blank filled in when the message is
/// shown; `{timer:Sermon}` shows that timer's current value.
public struct MessageDefinition: Identifiable, Codable, Hashable, Sendable {
    public enum Position: String, Codable, Hashable, Sendable, CaseIterable {
        case top
        case bottom
    }

    public let id: UUID
    public var name: String
    public var text: String
    public var position: Position
    /// Points on the 1920×1080 canvas.
    public var fontSize: Double
    public var textColor: RGBAColor
    /// The bar behind the text.
    public var barColor: RGBAColor

    public init(
        id: UUID = UUID(),
        name: String,
        text: String,
        position: Position = .bottom,
        fontSize: Double = 64,
        textColor: RGBAColor = .white,
        barColor: RGBAColor = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.75)
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.position = position
        self.fontSize = fontSize
        self.textColor = textColor
        self.barColor = barColor
    }

    public static func defaults() -> [MessageDefinition] {
        [MessageDefinition(name: "Nursery", text: "Parent of child {Number}, please come to the nursery")]
    }

    /// The blanks to fill in when showing the message, in order, without duplicates or timers.
    public var fields: [String] {
        var names: [String] = []
        for token in Self.tokens(in: text) where !token.lowercased().hasPrefix("timer:") && !names.contains(token) {
            names.append(token)
        }
        return names
    }

    /// The text with blanks filled in and timers replaced by `timerText(name)`. Unknown values stay empty.
    public func rendered(values: [String: String], timerText: (String) -> String?) -> String {
        var result = text
        for token in Self.tokens(in: text) {
            let replacement: String
            if token.lowercased().hasPrefix("timer:") {
                let name = String(token.dropFirst("timer:".count)).trimmingCharacters(in: .whitespaces)
                replacement = timerText(name) ?? ""
            } else {
                replacement = values[token] ?? ""
            }
            result = result.replacingOccurrences(of: "{\(token)}", with: replacement)
        }
        return result
    }

    private static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var scanner = text[...]
        while let open = scanner.firstIndex(of: "{"), let close = scanner[open...].firstIndex(of: "}") {
            let token = String(scanner[scanner.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if !token.isEmpty { tokens.append(token) }
            scanner = scanner[scanner.index(after: close)...]
        }
        return tokens
    }
}

/// A message on the audience output with its blanks filled in.
public struct ActiveMessage: Equatable, Sendable {
    public var messageID: UUID
    public var values: [String: String]

    public init(messageID: UUID, values: [String: String] = [:]) {
        self.messageID = messageID
        self.values = values
    }
}

extension PresentationDocument {
    /// The library of props: each slide is one prop (its label is the prop's name), drawn over the slides
    /// when shown. Kept out of the playlist and library; edited in the slide editor.
    public static func propsLibrary() -> PresentationDocument {
        var logo = SlideDocument(
            elements: [.text(TextElement(text: "Our Church", role: .caption,
                                         box: TextBox(frame: NormalizedRect(x: 0.72, y: 0.04, width: 0.25, height: 0.08))))],
            background: .transparent
        )
        logo.label = "Logo"
        return PresentationDocument(title: "Props", slides: [logo], background: .transparent)
    }
}
