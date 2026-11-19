import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

extension XMLParser {
    /// A parser for a whole document in memory. Off Apple platforms Foundation hands a parser made with `init(data:)`
    /// to libxml2 in one piece, and libxml2 turns down a piece over 10 MB ("huge input lookup", reported as an internal
    /// error at the end of the document), so every full Bible from eBible.org failed on Windows. Read from a stream,
    /// it goes in 128 KB pieces. Apple's parser has no such limit and keeps reading the data directly.
    static func reading(_ data: Data) -> XMLParser {
        #if canImport(FoundationXML)
        XMLParser(stream: InputStream(data: data))
        #else
        XMLParser(data: data)
        #endif
    }

    /// Parses the document and says whether it was well formed. Off Apple platforms Foundation parses in libxml2's
    /// recovery mode: `parse()` returns true for a damaged file (an element left open, a mismatched end tag) and only
    /// records the error in `parserError`. Apple's stops with false. Checking both rejects the same files everywhere.
    func parseStrictly() -> Bool {
        parse() && parserError == nil
    }
}
