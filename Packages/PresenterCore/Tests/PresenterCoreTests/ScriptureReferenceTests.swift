import Foundation
import XCTest
@testable import PresenterCore

final class ScriptureReferenceTests: XCTestCase {
    private typealias Point = ScriptureReference.Point
    private typealias Span = ScriptureReference.Span

    private func parse(_ text: String) throws -> ScriptureReference {
        try ScriptureReference.parse(text)
    }

    private func verses(_ chapter: Int, _ from: Int, _ to: Int? = nil) -> Span {
        Span(from: Point(chapter: chapter, verse: from), to: Point(chapter: chapter, verse: to ?? from))
    }

    // MARK: Books

    func testEveryBookIsFoundByItsNamesInBothLanguages() {
        for book in BibleBook.all {
            XCTAssertEqual(BibleBookLookup.match(book.english), .book(book), book.english)
            XCTAssertEqual(BibleBookLookup.match(book.spanish), .book(book), book.spanish)
            XCTAssertEqual(BibleBook.osis(book.osis), book)
            XCTAssertEqual(BibleBook.number(book.number), book)
        }
        XCTAssertEqual(BibleBook.all.count, 66)
    }

    func testNoAbbreviationNamesTwoBooks() {
        var seen: [String: Int] = [:]
        for book in BibleBook.all {
            for abbreviation in book.abbreviations {
                XCTAssertNil(seen[abbreviation], "“\(abbreviation)” is used by books \(seen[abbreviation] ?? 0) and \(book.number)")
                seen[abbreviation] = book.number
            }
        }
    }

    func testAbbreviationsThatCouldMeanTwoBooks() {
        let expected = [
            "Jn": "John", "Jon": "Jonah", "Jud": "Jude", "Jue": "Judges", "Fil": "Philippians", "Flm": "Philemon",
            "Sal": "Psalms", "Ap": "Revelation", "Cnt": "Song of Songs",
        ]
        for (typed, english) in expected {
            XCTAssertEqual(BibleBookLookup.match(typed), .book(BibleBook.all.first { $0.english == english }!), typed)
        }
    }

    func testAccentsCaseOrdinalsAndUniqueStarts() {
        let firstCorinthians = BibleBook.number(46)!
        for typed in ["1 Co", "1co", "I Corintios", "1ra de Corintios", "Primera Corintios", "First Corinthians", "1 cor."] {
            XCTAssertEqual(BibleBookLookup.match(typed), .book(firstCorinthians), typed)
        }
        XCTAssertEqual(BibleBookLookup.match("génesis"), .book(BibleBook.number(1)!))
        XCTAssertEqual(BibleBookLookup.match("GENESIS"), .book(BibleBook.number(1)!))
        XCTAssertEqual(BibleBookLookup.match("Apoc"), .book(BibleBook.number(66)!))
        XCTAssertEqual(BibleBookLookup.match("Salmo"), .book(BibleBook.number(19)!), "Singular is a start of Salmos")
        XCTAssertEqual(BibleBookLookup.match("Psalm"), .book(BibleBook.number(19)!))
        XCTAssertEqual(BibleBookLookup.match("Isaias"), .book(BibleBook.number(23)!))
        guard case .ambiguous(let books) = BibleBookLookup.match("Jo") else { return XCTFail("“Jo” should be ambiguous") }
        XCTAssertTrue(books.contains { $0.english == "Job" })
        XCTAssertEqual(BibleBookLookup.match("Xyz"), .none)
    }

    // MARK: References

    func testCommonReferences() throws {
        let john = BibleBook.number(43)!
        XCTAssertEqual(try parse("Juan 3:16-18"), ScriptureReference(book: john, spans: [verses(3, 16, 18)]))
        XCTAssertEqual(try parse("Jn 3:16"), ScriptureReference(book: john, spans: [verses(3, 16)]))
        XCTAssertEqual(try parse("John 3.16"), ScriptureReference(book: john, spans: [verses(3, 16)]))
        XCTAssertEqual(try parse("1 Co 13:4-7"), ScriptureReference(book: BibleBook.number(46)!, spans: [verses(13, 4, 7)]))
        XCTAssertEqual(try parse("Salmo 23"),
                       ScriptureReference(book: BibleBook.number(19)!, spans: [Span(from: Point(chapter: 23), to: Point(chapter: 23))]))
    }

    func testRangesListsAndSeveralChapters() throws {
        XCTAssertEqual(try parse("Juan 3:16–4:2").spans, [Span(from: Point(chapter: 3, verse: 16), to: Point(chapter: 4, verse: 2))])
        XCTAssertEqual(try parse("Juan 3 - 4").spans, [Span(from: Point(chapter: 3), to: Point(chapter: 4))])
        XCTAssertEqual(try parse("Juan 3:16, 18, 20-21").spans, [verses(3, 16), verses(3, 18), verses(3, 20, 21)])
        XCTAssertEqual(try parse("Mateo 5:3-12; 6:9-13").spans, [verses(5, 3, 12), verses(6, 9, 13)])
        XCTAssertEqual(try parse("Salmos 23, 100").spans,
                       [Span(from: Point(chapter: 23), to: Point(chapter: 23)), Span(from: Point(chapter: 100), to: Point(chapter: 100))])
        XCTAssertEqual(try parse("Juan 3:16,").spans, [verses(3, 16)], "A stray comma is ignored")
    }

    func testErrors() {
        XCTAssertThrowsError(try parse("  ")) { XCTAssertEqual($0 as? ScriptureReference.ParseError, .empty) }
        XCTAssertThrowsError(try parse("Juan")) {
            XCTAssertEqual($0 as? ScriptureReference.ParseError, .missingChapter(BibleBook.number(43)!))
        }
        XCTAssertThrowsError(try parse("Hezekiah 3:1")) {
            XCTAssertEqual($0 as? ScriptureReference.ParseError, .unknownBook("Hezekiah"))
        }
        XCTAssertThrowsError(try parse("Jo 3:16")) {
            guard case .ambiguousBook("Jo", _)? = $0 as? ScriptureReference.ParseError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try parse("Juan 3:18-16")) {
            XCTAssertEqual($0 as? ScriptureReference.ParseError, .backwards("3:18-16"))
        }
        XCTAssertThrowsError(try parse("Juan 3:x")) {
            XCTAssertEqual($0 as? ScriptureReference.ParseError, .unreadable("3:x"))
        }
        XCTAssertThrowsError(try parse("Juan 0:1"))
        XCTAssertEqual(ScriptureReference.ParseError.missingChapter(BibleBook.number(43)!).message(in: .spanish),
                       "Falta el capítulo: Juan 1.")
    }

    func testFormatting() throws {
        XCTAssertEqual(try parse("jn 3:16-18").formatted(in: .spanish), "Juan 3:16-18")
        XCTAssertEqual(try parse("juan 3:16-18").formatted(in: .english), "John 3:16-18")
        XCTAssertEqual(try parse("Juan 3:16, 18; 4:1").formatted(in: .english), "John 3:16, 18; 4:1")
        XCTAssertEqual(try parse("Juan 3:16-4:2").formatted(in: .english), "John 3:16–4:2")
        XCTAssertEqual(try parse("ps 23").formatted(in: .english), "Psalms 23")
        XCTAssertEqual(try parse("Juan 3-4").formatted(in: .spanish), "Juan 3-4")
        XCTAssertEqual(try parse("1 co 13:4-7").formatted(in: .spanish), "1 Corintios 13:4-7")
    }
}
