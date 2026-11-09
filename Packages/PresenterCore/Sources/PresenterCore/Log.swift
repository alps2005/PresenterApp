#if canImport(os)
import os

/// The core's loggers, under the app's subsystem so Console shows them together.
enum Log {
    static let coordinator = Logger(subsystem: "io.github.alps2005.Presenter", category: "PresentationCoordinator")
}
#else
import Foundation

/// Off Apple platforms (Windows, Linux) there's no unified log: the same calls write to standard error.
enum Log {
    static let coordinator = Logger(category: "PresentationCoordinator")
}

/// A stand-in for `os.Logger` with the calls the core makes. The `privacy:` of an interpolation is accepted and
/// ignored: standard error isn't shared like the unified log.
struct Logger: Sendable {
    let category: String

    func debug(_ message: LogMessage) { write("debug", message) }
    func info(_ message: LogMessage) { write("info", message) }
    func notice(_ message: LogMessage) { write("notice", message) }
    func error(_ message: LogMessage) { write("error", message) }
    func fault(_ message: LogMessage) { write("fault", message) }

    private func write(_ level: String, _ message: LogMessage) {
        // Not write(_:), which ends the program if the write fails. A Windows app started by double-clicking has no
        // standard error, so every write fails, and a log line must never stop a service.
        try? FileHandle.standardError.write(contentsOf: Data("[\(category)] \(level): \(message.text)\n".utf8))
    }
}

/// `os.OSLogPrivacy`'s names, so the same log lines compile everywhere.
struct LogPrivacy: Sendable {
    static let `public` = LogPrivacy()
    static let `private` = LogPrivacy()
    static let auto = LogPrivacy()
}

/// A log line built by string interpolation, like `OSLogMessage`.
struct LogMessage: ExpressibleByStringInterpolation {
    let text: String

    init(stringLiteral value: String) {
        text = value
    }

    init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
    }

    struct Interpolation: StringInterpolationProtocol {
        var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        mutating func appendInterpolation<Value>(_ value: Value, privacy: LogPrivacy = .auto) {
            text += String(describing: value)
        }
    }
}
#endif
