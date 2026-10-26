import Foundation
import XCTest
@testable import PresenterCore

/// Verses from the King James Version, which is in the public domain.
@MainActor
final class ScriptureTests: XCTestCase {
    private func kjv() -> BibleTranslation {
        BibleTranslation(name: "King James Version", abbreviation: "KJV", language: .english, books: [
            .init(number: 43, chapters: [
                .init(number: 3, verses: [
                    .init(number: 16, text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
                    .init(number: 17, text: "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."),
                    .init(number: 18, text: "He that believeth on him is not condemned."),
                ]),
            ]),
            .init(number: 19, chapters: [
                .init(number: 23, verses: [.init(number: 1, text: "The LORD is my shepherd; I shall not want.")]),
            ]),
        ])
    }

    private func passage(_ reference: String) throws -> BiblePassage {
        try kjv().passage(for: ScriptureReference.parse(reference))
    }

    // MARK: Store

    func testStoreSavesListsLoadsAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bibles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BibleStore(directory: directory)
        XCTAssertEqual(store.entries(), [])

        let bible = kjv()
        let entry = try store.save(bible)
        XCTAssertEqual(entry.abbreviation, "KJV")
        XCTAssertEqual(entry.verseCount, 4)
        XCTAssertEqual(store.entries(), [entry])
        XCTAssertEqual(try store.load(bible.id), bible)

        var renamed = bible
        renamed.abbreviation = "AV"
        try store.save(renamed)
        XCTAssertEqual(store.entries().map(\.abbreviation), ["AV"], "Saving the same translation replaces it")

        try store.delete(bible.id)
        XCTAssertEqual(store.entries(), [])
        XCTAssertThrowsError(try store.load(bible.id)) { XCTAssertEqual($0 as? BibleStore.StoreError, .notFound) }
    }

    // MARK: Search

    func testSearchMatchesEveryWordIgnoringCaseAndAccents() {
        let hits = BibleSearch.search("WORLD saved", in: kjv())
        XCTAssertEqual(hits.map(\.verse), [17])
        XCTAssertEqual(hits.first?.reference(in: .spanish), "Juan 3:17")
        XCTAssertEqual(BibleSearch.search("believeth", in: kjv()).map(\.verse), [16, 18])
        XCTAssertEqual(BibleSearch.search("believeth", in: kjv(), limit: 1).count, 1)
        XCTAssertEqual(BibleSearch.search("   ", in: kjv()), [])
        let spanish = BibleTranslation(name: "R", abbreviation: "R", language: .spanish, books: [
            .init(number: 43, chapters: [.init(number: 3, verses: [.init(number: 16, text: "Porque de tal manera amó Dios al mundo")])]),
        ])
        XCTAssertEqual(BibleSearch.search("amo dios", in: spanish).count, 1)
    }

    // MARK: Slides

    func testVersesPerSlideNumbersAndCaptions() throws {
        let slides = ScriptureSlides.make(try passage("John 3:16-18"), options: .init(versesPerSlide: 2, maxCharactersPerSlide: 1000))
        XCTAssertEqual(slides.count, 2)
        XCTAssertEqual(slides.map(\.label), [nil, nil], "Labels are for song sections")
        XCTAssertTrue(slides[0].primaryText.hasPrefix("¹⁶ For God so loved"))
        XCTAssertTrue(slides[0].primaryText.contains(" ¹⁷ For God sent not"))
        guard case .text(let caption) = slides[1].elements.last else { return XCTFail("No caption") }
        XCTAssertEqual(caption.role, .caption)
        XCTAssertEqual(caption.text, "John 3:18 · KJV")

        let plain = ScriptureSlides.make(try passage("Ps 23:1"), options: .init(showsVerseNumbers: false, showsReference: false))
        XCTAssertEqual(plain.count, 1)
        XCTAssertEqual(plain[0].elements.count, 1)
        XCTAssertEqual(plain[0].primaryText, "The LORD is my shepherd; I shall not want.")
    }

    func testLongVersesSplitAtABreak() throws {
        let slides = ScriptureSlides.make(try passage("John 3:16"), options: .init(versesPerSlide: 1, maxCharactersPerSlide: 90))
        XCTAssertEqual(slides.count, 2)
        XCTAssertTrue(slides[0].primaryText.hasPrefix("¹⁶ "), "Only the first part is numbered")
        XCTAssertFalse(slides[1].primaryText.hasPrefix("¹⁶"))
        XCTAssertTrue(slides[0].primaryText.hasSuffix(","), "Split after a comma, not mid-phrase")
        guard case .text(let caption) = slides[1].elements.last else { return XCTFail("No caption") }
        XCTAssertEqual(caption.text, "John 3:16 · KJV", "Both parts carry the verse's reference")
        XCTAssertEqual(ScriptureSlides.split("short", max: 80), ["short"])
        XCTAssertEqual(ScriptureSlides.superscript(120), "¹²⁰")
    }

    func testCharacterLimitStartsANewSlide() throws {
        let slides = ScriptureSlides.make(try passage("John 3:16-18"), options: .init(versesPerSlide: 4, maxCharactersPerSlide: 160))
        XCTAssertEqual(slides.count, 2, "Verses 16 and 17 together are too long for one slide")
        XCTAssertEqual(slides.compactMap { slide -> String? in
            if case .text(let caption) = slide.elements.last { caption.text } else { nil }
        }, ["John 3:16 · KJV", "John 3:17-18 · KJV"])
    }

    // MARK: Adding to the show

    func testAddScriptureMakesAPresentationWithTheTheme() throws {
        let c = PresentationCoordinator(project: .starter())
        let themeID = try XCTUnwrap(c.suggestedScriptureThemeID)
        XCTAssertEqual(c.project.theme(withID: themeID)?.name, "Scripture")

        let item = try XCTUnwrap(c.addScripture(try passage("John 3:16-17"), themeID: themeID))
        let presentation = try XCTUnwrap(c.project.presentation(forItem: item.id))
        XCTAssertEqual(presentation.title, "John 3:16-17 · KJV")
        XCTAssertEqual(presentation.themeID, themeID)
        XCTAssertEqual(presentation.kind, .scripture)
        XCTAssertEqual(c.state.selectedItemID, item.id)
        XCTAssertEqual(c.project.playlist.items.last?.id, item.id)

        c.undo()
        XCTAssertNil(c.project.presentation(withID: presentation.id))
        XCTAssertNil(c.addScripture(BiblePassage(reference: try ScriptureReference.parse("Jn 1"), translationName: "", translationAbbreviation: "",
                                                 language: .english, verses: []), themeID: nil))
    }
}
