import Foundation

/// Words in braces that stand for something else: `{Number}` blanks and `{timer:Sermon}` in messages, and the live
/// values slides can show.
public enum TextTokens {
    /// The tokens in `text`, in order, without their braces and trimmed. Empty braces are skipped.
    public static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var scanner = text[...]
        while let open = scanner.firstIndex(of: "{"), let close = scanner[open...].firstIndex(of: "}") {
            let token = String(scanner[scanner.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if !token.isEmpty { tokens.append(token) }
            scanner = scanner[scanner.index(after: close)...]
        }
        return tokens
    }

    /// The timer a `{timer:Name}` token names, or nil for any other token.
    public static func timerName(_ token: String) -> String? {
        guard token.lowercased().hasPrefix("timer:") else { return nil }
        return String(token.dropFirst("timer:".count)).trimmingCharacters(in: .whitespaces)
    }

    /// `text` with each token replaced by `replacement(token)`. Tokens it returns nil for stay as they are.
    public static func replacing(in text: String, _ replacement: (String) -> String?) -> String {
        var result = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let token = String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            result += rest[..<open]
            if !token.isEmpty, let value = replacement(token) {
                result += value
            } else {
                result += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }
}

/// The live values a slide's text can show, updated on the audience output as they change: `{timer:Sermon}`,
/// `{clock}` (hours and minutes) and `{clock:seconds}`. Other braces stay as typed, so lyrics are safe.
public enum LiveText {
    public enum Token: Equatable, Sendable {
        case timer(String)
        case clock(seconds: Bool)
    }

    public static func token(_ token: String) -> Token? {
        if let name = TextTokens.timerName(token) { return .timer(name) }
        switch token.lowercased() {
        case "clock": return .clock(seconds: false)
        case "clock:seconds": return .clock(seconds: true)
        default: return nil
        }
    }

    /// True when `text` has a live value, so it needs redrawing as time passes.
    public static func hasTokens(_ text: String) -> Bool {
        text.contains("{") && TextTokens.tokens(in: text).contains { token($0) != nil }
    }

    /// The timer names `text` refers to.
    public static func timerNames(in text: String) -> [String] {
        TextTokens.tokens(in: text).compactMap { if case .timer(let name) = token($0) { name } else { nil } }
    }

    /// `text` with its live values filled in at `date`. A timer that doesn't exist shows nothing.
    public static func resolve(_ text: String, at date: Date, timerText: (String) -> String?,
                               calendar: Calendar = .current) -> String {
        guard text.contains("{") else { return text }
        return TextTokens.replacing(in: text) { raw in
            switch token(raw) {
            case .timer(let name): timerText(name) ?? ""
            case .clock(let seconds): clockText(date, seconds: seconds, calendar: calendar)
            case nil: nil
            }
        }
    }

    /// "9:41" or "9:41:07", in the Mac's 12- or 24-hour style.
    public static func clockText(_ date: Date, seconds: Bool, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        if seconds { style = style.second() }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
