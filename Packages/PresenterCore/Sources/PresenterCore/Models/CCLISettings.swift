import Foundation

/// The church's CCLI licence, and whether songs show their credits on screen, as CCLI asks: on a song's first and
/// last slides. Kept in the project.
public struct CCLISettings: Codable, Hashable, Sendable {
    /// The church's CCLI licence number, digits only. Empty when the church hasn't entered one.
    public var licenseNumber: String
    /// Songs with credits show a line with their title, writers, copyright and CCLI numbers on their first and last
    /// slides.
    public var showsCredits: Bool

    public init(licenseNumber: String = "", showsCredits: Bool = true) {
        self.licenseNumber = licenseNumber
        self.showsCredits = showsCredits
    }

    private enum CodingKeys: String, CodingKey {
        case licenseNumber, showsCredits
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        licenseNumber = try container.decodeIfPresent(String.self, forKey: .licenseNumber) ?? ""
        showsCredits = try container.decodeIfPresent(Bool.self, forKey: .showsCredits) ?? true
    }
}

extension SongInfo {
    /// The credit line a song shows on screen: “Amazing Grace” · John Newton · © Public Domain · CCLI Song # 22025 ·
    /// CCLI License # 123456. Parts nobody filled in are left out.
    public func creditLine(title: String, licenseNumber: String) -> String {
        var parts: [String] = []
        if !title.isEmpty { parts.append("“\(title)”") }
        if !authors.isEmpty { parts.append(authorLine) }
        if !copyright.isEmpty {
            parts.append(copyright.lowercased().hasPrefix("public domain") ? copyright : "© \(copyright)")
        }
        if !ccliNumber.isEmpty { parts.append("CCLI Song # \(ccliNumber)") }
        if !licenseNumber.isEmpty { parts.append("CCLI License # \(licenseNumber)") }
        return parts.joined(separator: " · ")
    }
}
