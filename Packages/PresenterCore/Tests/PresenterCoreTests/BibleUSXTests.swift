import Foundation
import XCTest
@testable import PresenterCore

/// USFX and USX, the formats eBible.org and the Digital Bible Library share open translations in. Fixtures use the
/// World English Bible, which is in the public domain.
final class BibleUSXTests: XCTestCase {
    private let usfx = """
    <?xml version="1.0" encoding="utf-8"?>
    <usfx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <languageCode>eng</languageCode>
    <book id="JHN">
    <id id="JHN">World English Bible</id>
    <h>John</h>
    <toc level="1">The Good News According to John</toc>
    <c id="3"/>
    <s>Jesus and Nicodemus</s>
    <p><v id="16"/>For God so loved the world, that he gave his one and only Son,<f caller="+">A note.</f> that whoever
    believes in him should not perish, but have eternal life.<ve/>
    <v id="17"/>For God didn’t send his Son into the world to judge the world, but that the world should be saved through him.<ve/></p>
    </book>
    <book id="PSA">
    <h>Psalms</h>
    <c id="23"/>
    <d>A Psalm by David.</d>
    <q><v id="1"/>Yahweh is my shepherd;</q>
    <q>I shall lack nothing.<ve/></q>
    </book>
    <book id="TOB"><c id="1"/><p><v id="1"/>Not one of the 66.<ve/></p></book>
    </usfx>
    """

    private let johnUSX3 = """
    <?xml version="1.0" encoding="utf-8"?>
    <usx version="3.0">
      <book code="JHN" style="id">World English Bible</book>
      <para style="h">John</para>
      <para style="toc1">The Good News According to John</para>
      <para style="mt1">The Good News According to John</para>
      <chapter number="3" style="c" sid="JHN 3"/>
      <para style="s1">Jesus and Nicodemus</para>
      <para style="p"><verse number="16" style="v" sid="JHN 3:16"/>For God so loved the world,<note caller="+" style="f"><char style="ft">A note.</char></note> that he gave his one and only <char style="w" strong="G5207">Son</char>, that whoever believes in him should not perish, but have eternal life.<verse eid="JHN 3:16"/>
      <verse number="17" style="v" sid="JHN 3:17"/>For God didn’t send his Son into the world to judge the world,</para>
      <para style="q1">but that the world should be saved through him.<verse eid="JHN 3:17"/></para>
      <chapter eid="JHN 3"/>
    </usx>
    """

    /// USX 2 has no verse end markers; a verse runs to the next one. "2-3" is a verse range.
    private let genesisUSX2 = """
    <usx version="2.5"><book code="GEN" style="id"/><chapter number="1" style="c"/><para style="ip">An introduction.</para>
    <para style="p"><verse number="1" style="v"/>In the beginning, God created the heavens and the earth. <verse number="2-3" style="v"/>The earth was formless and empty.</para></usx>
    """

    private let metadata = """
    <?xml version="1.0" encoding="utf-8"?>
    <DBLMetadata id="2880c78491b2f8ce" revision="1">
      <identification><name>World English Bible</name><nameLocal>World English Bible</nameLocal><abbreviation>engweb</abbreviation><abbreviationLocal>WEB</abbreviationLocal></identification>
      <language><iso>eng</iso><name>English</name></language>
      <agencies><rightsHolder><name>eBible.org</name></rightsHolder></agencies>
    </DBLMetadata>
    """

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testUSFX() throws {
        let bible = try BibleFileParser.parse(data(usfx))
        XCTAssertEqual(bible.language, .english)
        let john = try XCTUnwrap(bible.book(43)?.chapter(3))
        XCTAssertEqual(john.verses.map(\.number), [16, 17])
        XCTAssertEqual(john.verses[0].text,
                       "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.",
                       "Notes are left out and line breaks become spaces")
        XCTAssertFalse(john.verses.contains { $0.text.contains("Nicodemus") }, "Headings aren't verse text")
        XCTAssertEqual(bible.book(19)?.chapter(23)?.verses.first?.text, "Yahweh is my shepherd; I shall lack nothing.",
                       "A verse across poetry lines, without the psalm's title")
        XCTAssertEqual(bible.verseCount, 3, "Books outside the 66 are left out")
    }

    func testUSXBooksAndMetadataMakeOneTranslation() throws {
        let bible = try BibleFileParser.parse([data(metadata), data(johnUSX3), data(genesisUSX2), data("<html/>")])
        XCTAssertEqual(bible.name, "World English Bible")
        XCTAssertEqual(bible.abbreviation, "WEB")
        XCTAssertEqual(bible.language, .english)

        let john = try XCTUnwrap(bible.book(43)?.chapter(3))
        XCTAssertEqual(john.verses[0].text,
                       "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.")
        XCTAssertEqual(john.verses[1].text,
                       "For God didn’t send his Son into the world to judge the world, but that the world should be saved through him.",
                       "A verse across paragraphs")

        let genesis = try XCTUnwrap(bible.book(1)?.chapter(1))
        XCTAssertEqual(genesis.verses.map(\.number), [1, 2])
        XCTAssertEqual(genesis.verses[0].text, "In the beginning, God created the heavens and the earth.", "The introduction is left out")
        XCTAssertEqual(genesis.verses[1].text, "The earth was formless and empty.")
    }

    func testUSXWithoutMetadataIsNamedLater() throws {
        let bible = try BibleFileParser.parse([data(genesisUSX2)])
        XCTAssertEqual(bible.name, "Imported Bible")
        XCTAssertThrowsError(try BibleFileParser.parse([data(metadata)])) {
            XCTAssertEqual($0 as? BibleFileParser.ParseError, .notABible, "Metadata alone isn't a Bible")
        }
    }

    func testBookCodes() {
        XCTAssertEqual(BibleBook.usfm("GEN")?.number, 1)
        XCTAssertEqual(BibleBook.usfm("jhn")?.number, 43)
        XCTAssertEqual(BibleBook.usfm("REV")?.number, 66)
        XCTAssertNil(BibleBook.usfm("TOB"))
        XCTAssertEqual(BibleBook.usfmCodes.count, 66)
    }

    func testNonVerseStyles() {
        for style in ["h", "toc1", "mt1", "ms", "mr", "s", "s2", "sr", "r", "d", "sp", "rem", "ip", "is1", "imt", "iot", "cl"] {
            XCTAssertTrue(BibleFileParser.isNonVerseStyle(style), style)
        }
        for style in ["p", "m", "mi", "q1", "q2", "pi1", "li1", "nb", "pc", "qr"] {
            XCTAssertFalse(BibleFileParser.isNonVerseStyle(style), style)
        }
    }

    func testStoreImportsAFolderOfBooks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("usx-\(UUID())", isDirectory: true)
        let books = folder.appendingPathComponent("release/USX_1", isDirectory: true)
        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try data(metadata).write(to: folder.appendingPathComponent("metadata.xml"))
        try data(genesisUSX2).write(to: books.appendingPathComponent("GEN.usx"))
        try data(johnUSX3).write(to: books.appendingPathComponent("JHN.usx"))
        try data("not a book").write(to: books.appendingPathComponent("notes.txt"))

        let store = BibleStore(directory: folder.appendingPathComponent("Bibles", isDirectory: true))
        let entry = try store.importFiles(at: [folder])
        XCTAssertEqual(entry.abbreviation, "WEB")
        XCTAssertEqual(entry.verseCount, 4)
    }
}
