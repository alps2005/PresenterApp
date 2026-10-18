import Foundation
import XCTest
@testable import PresenterCore

/// Fixtures use the King James Version and the Reina-Valera 1909, both in the public domain.
final class BibleFileParserTests: XCTestCase {
    private let zefania = """
    <?xml version="1.0" encoding="utf-8"?>
    <XMLBIBLE biblename="Reina-Valera 1909">
      <INFORMATION>
        <title>Reina-Valera 1909</title>
        <identifier>RVR1909</identifier>
        <language>SPA</language>
      </INFORMATION>
      <BIBLEBOOK bnumber="43" bname="Juan">
        <CHAPTER cnumber="3">
          <VERS vnumber="16">Porque de tal manera amó Dios al mundo, que haya dado á su Hijo unigénito,
            para que todo aquel que en él cree, no se pierda, mas tenga vida eterna.</VERS>
          <VERS vnumber="17">Porque no envió Dios á su Hijo al mundo, para que condene al mundo,<NOTE>Nota del editor.</NOTE>
            mas para que el mundo sea salvo por él.</VERS>
        </CHAPTER>
      </BIBLEBOOK>
    </XMLBIBLE>
    """

    /// Container verses for Genesis, milestone verses for John, a note and a heading that never reach a slide.
    private let osis = """
    <?xml version="1.0" encoding="UTF-8"?>
    <osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace">
      <osisText osisIDWork="KJV" xml:lang="en">
        <header><work osisWork="KJV"><title>King James Version</title></work></header>
        <div type="book" osisID="Gen">
          <chapter osisID="Gen.1">
            <title>The creation</title>
            <verse osisID="Gen.1.1">In the beginning God created the heaven and the earth.</verse>
            <verse osisID="Gen.1.2">And the earth was without form, and void;<note>Or, empty.</note> and darkness was upon the face of the deep.</verse>
            <verse osisID="Gen.1.3">And God said, Let there be light: and there was light.</verse>
          </chapter>
        </div>
        <div type="book" osisID="John">
          <chapter sID="John.3.seID.1" osisID="John.3"/>
          <verse sID="John.3.16.seID.2" osisID="John.3.16"/>For God so loved the world, that he gave his only begotten Son,
          that whosoever believeth in him should not perish, but have everlasting life.<verse eID="John.3.16.seID.2"/>
          <verse sID="John.3.17.seID.3" osisID="John.3.17"/>For God sent not his Son into the world to condemn the world;
          but that the world through him might be saved.<verse eID="John.3.17.seID.3"/>
          <chapter eID="John.3.seID.1"/>
        </div>
      </osisText>
    </osis>
    """

    private func parse(_ xml: String) throws -> BibleTranslation {
        try BibleFileParser.parse(Data(xml.utf8))
    }

    func testZefania() throws {
        let bible = try parse(zefania)
        XCTAssertEqual(bible.name, "Reina-Valera 1909")
        XCTAssertEqual(bible.abbreviation, "RVR1909")
        XCTAssertEqual(bible.language, .spanish)
        let chapter = try XCTUnwrap(bible.book(43)?.chapter(3))
        XCTAssertEqual(chapter.verses.map(\.number), [16, 17])
        XCTAssertTrue(chapter.verses[0].text.hasPrefix("Porque de tal manera amó Dios al mundo, que haya dado á su Hijo unigénito, para que"),
                      "Line breaks inside a verse become single spaces")
        XCTAssertEqual(chapter.verses[1].text,
                       "Porque no envió Dios á su Hijo al mundo, para que condene al mundo, mas para que el mundo sea salvo por él.",
                       "Notes are left out")
    }

    func testOSISContainerAndMilestoneVerses() throws {
        let bible = try parse(osis)
        XCTAssertEqual(bible.name, "King James Version")
        XCTAssertEqual(bible.abbreviation, "KJV")
        XCTAssertEqual(bible.language, .english)
        let genesis = try XCTUnwrap(bible.book(1)?.chapter(1))
        XCTAssertEqual(genesis.verses.map(\.number), [1, 2, 3])
        XCTAssertEqual(genesis.verses[1].text, "And the earth was without form, and void; and darkness was upon the face of the deep.")
        XCTAssertFalse(genesis.verses.contains { $0.text.contains("creation") }, "Headings aren't verse text")
        let john = try XCTUnwrap(bible.book(43)?.chapter(3))
        XCTAssertEqual(john.verses.map(\.number), [16, 17])
        XCTAssertEqual(john.verses[1].text,
                       "For God sent not his Son into the world to condemn the world; but that the world through him might be saved.")
        XCTAssertEqual(bible.verseCount, 5)
    }

    func testFilesThatArentBibles() {
        XCTAssertThrowsError(try parse("<html><body>Hi</body></html>")) {
            XCTAssertEqual($0 as? BibleFileParser.ParseError, .notABible)
        }
        XCTAssertThrowsError(try parse("not xml at all")) {
            XCTAssertEqual($0 as? BibleFileParser.ParseError, .notABible)
        }
        XCTAssertThrowsError(try parse("<XMLBIBLE><BIBLEBOOK bnumber=\"1\"></BIBLEBOOK></XMLBIBLE>")) {
            XCTAssertEqual($0 as? BibleFileParser.ParseError, .noVerses)
        }
        XCTAssertThrowsError(try parse("<XMLBIBLE><BIBLEBOOK bnumber=\"1\"><CHAPTER cnumber=\"1\">")) {
            guard case .malformed? = $0 as? BibleFileParser.ParseError else { return XCTFail("\($0)") }
        }
    }

    func testExternalEntitiesAreNeverRead() throws {
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("bible-entity-\(UUID()).txt")
        try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secret) }
        let xml = """
        <?xml version="1.0"?>
        <!DOCTYPE XMLBIBLE [<!ENTITY leak SYSTEM "\(secret.absoluteString)">]>
        <XMLBIBLE><BIBLEBOOK bnumber="1"><CHAPTER cnumber="1"><VERS vnumber="1">In the beginning &leak;</VERS></CHAPTER></BIBLEBOOK></XMLBIBLE>
        """
        let text = try? parse(xml).book(1)?.chapter(1)?.verses.first?.text
        XCTAssertFalse(text?.contains("SECRET") ?? false)
    }

    // MARK: Passages

    func testPassagesAndTheirLimits() throws {
        let bible = try parse(osis)
        let passage = try bible.passage(for: ScriptureReference.parse("Gen 1:2-3"))
        XCTAssertEqual(passage.verses.map(\.number), [2, 3])
        XCTAssertEqual(passage.caption, "Genesis 1:2-3 · KJV")
        XCTAssertEqual(try bible.passage(for: ScriptureReference.parse("Genesis 1")).verses.count, 3, "A whole chapter")
        XCTAssertEqual(try bible.passage(for: ScriptureReference.parse("Gen 1:1, 1-2")).verses.map(\.number), [1, 2],
                       "A verse asked for twice is shown once")

        let spanish = try parse(zefania)
        XCTAssertEqual(try spanish.passage(for: ScriptureReference.parse("Jn 3:16-17")).caption, "Juan 3:16-17 · RVR1909")

        XCTAssertThrowsError(try bible.passage(for: ScriptureReference.parse("Exodus 1:1"))) {
            XCTAssertEqual($0 as? BiblePassageError, .bookMissing(BibleBook.number(2)!))
        }
        XCTAssertThrowsError(try bible.passage(for: ScriptureReference.parse("Gen 2:1"))) {
            XCTAssertEqual($0 as? BiblePassageError, .chapterMissing(BibleBook.number(1)!, 2))
        }
        XCTAssertThrowsError(try bible.passage(for: ScriptureReference.parse("Gen 1:2-9"))) {
            XCTAssertEqual($0 as? BiblePassageError, .verseMissing(BibleBook.number(1)!, chapter: 1, verse: 9))
        }
        XCTAssertEqual(BiblePassageError.chapterMissing(BibleBook.number(43)!, 30).message(in: .spanish), "Juan no tiene capítulo 30.")
    }
}
