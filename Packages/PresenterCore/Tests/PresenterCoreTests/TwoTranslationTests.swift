import XCTest
@testable import PresenterCore

/// The KJV is in the public domain; the Spanish lines are the Reina-Valera 1909, also in the public domain.
@MainActor
final class TwoTranslationTests: XCTestCase {
    private let kjv = BibleTranslation(name: "King James Version", abbreviation: "KJV", language: .english, books: [
        .init(number: 43, chapters: [.init(number: 3, verses: [
            .init(number: 16, text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
            .init(number: 17, text: "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."),
            .init(number: 18, text: "He that believeth on him is not condemned."),
        ])]),
    ])
    /// Verse 18 left out, as a Bible with different verse divisions might.
    private let rvr = BibleTranslation(name: "Reina-Valera 1909", abbreviation: "RVR1909", language: .spanish, books: [
        .init(number: 43, chapters: [.init(number: 3, verses: [
            .init(number: 16, text: "Porque de tal manera amó Dios al mundo, que ha dado á su Hijo unigénito, para que todo aquel que en él cree, no se pierda, mas tenga vida eterna."),
            .init(number: 17, text: "Porque no envió Dios á su Hijo al mundo, para que condene al mundo, mas para que el mundo sea salvo por él."),
        ])]),
    ])

    private func passages(_ reference: String) throws -> (BiblePassage, BiblePassage) {
        let parsed = try ScriptureReference.parse(reference)
        return (try rvr.passage(for: parsed), try kjv.passage(for: parsed))
    }

    private func texts(_ slide: SlideDocument) -> [String] {
        slide.elements.compactMap { if case .text(let text) = $0 { text.text } else { nil } }
    }

    func testBothTranslationsShowTheSameVersesStacked() throws {
        let (spanish, english) = try passages("Juan 3:16-17")
        let slides = ScriptureSlides.make(spanish, second: english,
                                          options: .init(versesPerSlide: 1, maxCharactersPerSlide: 600))
        XCTAssertEqual(slides.count, 2)
        let first = texts(slides[0])
        XCTAssertTrue(first[0].hasPrefix("¹⁶ Porque de tal manera"))
        XCTAssertTrue(first[1].hasPrefix("¹⁶ For God so loved"))
        XCTAssertEqual(first[2], "Juan 3:16 · RVR1909 / KJV")

        guard case .text(let top) = slides[0].elements[0], case .text(let bottom) = slides[0].elements[1] else {
            return XCTFail("Two text elements")
        }
        XCTAssertEqual(top.role, .body)
        XCTAssertEqual(top.overrides, [.box], "The theme styles the words but doesn't move them")
        XCTAssertLessThan(top.box!.frame.y + top.box!.frame.height, bottom.box!.frame.y)
        XCTAssertEqual(PresentationKind.guessed(for: PresentationDocument(title: "", slides: slides)), .scripture)
    }

    func testAVerseMissingFromTheSecondBibleLeavesItsHalfWithoutIt() throws {
        let parsed = try ScriptureReference.parse("John 3:17-18")
        let slides = ScriptureSlides.make(try kjv.passage(for: parsed), second: try rvr.passage(for: ScriptureReference.parse("Juan 3:17")),
                                          options: .init(versesPerSlide: 2, maxCharactersPerSlide: 600))
        XCTAssertEqual(slides.count, 1)
        let lines = texts(slides[0])
        XCTAssertTrue(lines[0].contains("¹⁸ He that believeth"))
        XCTAssertFalse(lines[1].contains("¹⁸"), "No verse 18 in the second Bible")
        XCTAssertTrue(lines[1].hasPrefix("¹⁷ Porque no envió"))
    }

    func testLongVersesSplitInStep() throws {
        let (spanish, english) = try passages("Juan 3:16")
        let slides = ScriptureSlides.make(spanish, second: english, options: .init(maxCharactersPerSlide: 180))
        XCTAssertGreaterThan(slides.count, 1, "Each half holds half as much, so the verse splits")
        for slide in slides {
            let lines = texts(slide)
            XCTAssertFalse(lines[0].isEmpty)
            XCTAssertFalse(lines[1].isEmpty, "Both translations go on to every part")
        }
        let joined = slides.map { texts($0)[1] }.joined(separator: " ")
        XCTAssertEqual(joined.replacingOccurrences(of: "¹⁶ ", with: ""), english.verses[0].text, "Nothing lost")
    }

    func testDivideKeepsTheCount() {
        XCTAssertEqual(ScriptureSlides.divide("one two three four", into: 2), ["one two", "three four"])
        XCTAssertEqual(ScriptureSlides.divide("word", into: 3), ["word", "", ""])
        XCTAssertEqual(ScriptureSlides.divide("a", into: 1), ["a"])
    }

    func testAddScriptureInTwoTranslations() throws {
        let (spanish, english) = try passages("Juan 3:16-17")
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let item = try XCTUnwrap(c.addScripture(spanish, second: english, themeID: nil))
        let presentation = try XCTUnwrap(c.project.presentation(forItem: item.id))
        XCTAssertEqual(presentation.title, "Juan 3:16-17 · RVR1909 / KJV")
        XCTAssertEqual(presentation.kind, .scripture)
    }

    func testOneTranslationIsUnchanged() throws {
        let english = try kjv.passage(for: ScriptureReference.parse("John 3:16"))
        let slide = try XCTUnwrap(ScriptureSlides.make(english, options: .init()).first)
        guard case .text(let body) = slide.elements[0] else { return XCTFail("Text") }
        XCTAssertNil(body.box)
        XCTAssertEqual(body.overrides, [])
        XCTAssertEqual(texts(slide).last, "John 3:16 · KJV")
    }
}
