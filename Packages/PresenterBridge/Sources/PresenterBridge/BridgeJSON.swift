import Foundation

/// The answer to a command: `{"ok": true, …values}` or `{"ok": false, "error": "…"}`.
struct BridgeReply: Encodable {
    enum Value: Encodable {
        case string(String)
        case int(Int)
        case list([[String: String]])

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .list(let value): try container.encode(value)
            }
        }
    }

    var ok: Bool
    var error: String?
    var values: [String: Value] = [:]

    static func success(_ values: [String: String] = [:]) -> BridgeReply {
        BridgeReply(ok: true, values: values.mapValues { .string($0) })
    }

    static func failure(_ message: String) -> BridgeReply {
        BridgeReply(ok: false, error: message)
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(ok, forKey: Key("ok"))
        try container.encodeIfPresent(error, forKey: Key("error"))
        for (key, value) in values { try container.encode(value, forKey: Key(key)) }
    }
}

enum BridgeJSON {
    /// Compact, with keys in a fixed order so the same state always reads the same.
    static func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            return #"{"ok":false,"error":"The engine couldn't describe its answer."}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A file URL as the platform writes paths: `C:\Users\…` on Windows, `/Users/…` on a Mac.
    static func path(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
    }
}
