import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension XMLParser {
    /// Parses the document and says whether it was well formed. Off Apple platforms Foundation parses in libxml2's
    /// recovery mode: `parse()` returns true for a damaged file (an element left open, a mismatched end tag) and only
    /// records the error in `parserError`. Apple's stops with false. Checking both rejects the same files everywhere.
    func parseStrictly() -> Bool {
        parse() && parserError == nil
    }
}
