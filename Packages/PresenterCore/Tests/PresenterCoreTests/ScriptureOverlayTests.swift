import Foundation
import XCTest
@testable import PresenterCore

/// Verses shown over the cued slide, from the King James Version, which is in the public domain.
@MainActor
final class ScriptureOverlayTests: XCTestCase {
    /// One presentation: before, sermon (a background and a countdown of its own), after.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let item: PresentationItem
        let before: SlideDocument
        let sermon: SlideDocument
        let after: SlideDocument

        func position(_ slide: SlideDocument) -> SlidePosition {
            SlidePosition(itemID: item.id, slideID: slide.id)
        }
    }

    private let sermonBackground = SlideBackground.color(RGBAColor(red: 0.2, green: 0.3, blue: 0.4))

    private func makeFixture() -> Fixture {
        let before = SlideDocument.text("Welcome")
        let sermon = SlideDocument(elements: SlideDocument.text("The Good News").elements, background: sermonBackground,
                                   goToNext: GoToNextTimer(seconds: 5))
        let after = SlideDocument.text("Offering")
        let presentation = PresentationDocument(title: "Sermon", slides: [before, sermon, after])
        let item = PresentationItem(presentationID: presentation.id)
        let project = ProjectDocument(name: "Test", presentations: [presentation],
                                      playlist: PlaylistDocument(title: "P", items: [item]))
        return Fixture(coordinator: PresentationCoordinator(project: project), item: item,
                       before: before, sermon: sermon, after: after)
    }

    private func passage(_ reference: String) throws -> BiblePassage {
        let kjv = BibleTranslation(name: "King James Version", abbreviation: "KJV", language: .english, books: [
            .init(number: 43, chapters: [
                .init(number: 3, verses: [
                    .init(number: 16, text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life."),
                    .init(number: 17, text: "For God sent not his Son into the world to condemn the world; but that the world through him might be saved."),
                    .init(number: 18, text: "He that believeth on him is not condemned."),
                ]),
            ]),
        ])
        return try kjv.passage(for: ScriptureReference.parse(reference))
    }

    private let onePerSlide = ScriptureSlides.Options(versesPerSlide: 1)

    private func texts(_ slide: SlideDocument?) -> [String] {
        slide?.elements.compactMap { element -> String? in
            if case .text(let text) = element { text.text } else { nil }
        } ?? []
    }

    /// Cues the sermon slide and shows John 3:16-18, one verse per page.
    private func showOverSermon(_ f: Fixture) throws {
        f.coordinator.cueSlide(f.sermon.id, inItem: f.item.id)
        let result = f.coordinator.showScripture(try passage("John 3:16-18"), options: onePerSlide,
                                                 themeID: f.coordinator.suggestedScriptureThemeID)
        XCTAssertEqual(result, .applied)
    }

    func testNeedsACuedSlide() throws {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.showScripture(try passage("John 3:16"), themeID: nil), .rejected(.nothingCued))
        XCTAssertNil(f.coordinator.state.live)
        XCTAssertNil(f.coordinator.state.scriptureOverlay)
    }

    func testShowsTheVersesOverTheCuedSlideWithoutAddingAnything() throws {
        let f = makeFixture()
        let projectBefore = f.coordinator.project
        try showOverSermon(f)

        let live = try XCTUnwrap(f.coordinator.state.live)
        XCTAssertEqual(live.position, f.position(f.sermon))
        XCTAssertEqual(texts(live.slide), ["The Good News", "¹⁶ For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.", "John 3:16 · KJV"])
        XCTAssertEqual(live.rendered.background, sermonBackground)
        XCTAssertEqual(f.coordinator.state.liveBackground, sermonBackground)
        XCTAssertEqual(f.coordinator.state.scriptureOverlay?.caption, "John 3:16-18 · KJV")
        XCTAssertEqual(f.coordinator.project, projectBefore)
        XCTAssertFalse(f.coordinator.canUndo)
        XCTAssertFalse(f.coordinator.liveSlideHasPendingEdits)
    }

    func testTheVersesFollowTheScriptureTheme() throws {
        let f = makeFixture()
        try showOverSermon(f)
        let theme = try XCTUnwrap(f.coordinator.suggestedScriptureThemeID.flatMap(f.coordinator.project.theme(withID:)))
        guard case .text(let verse)? = f.coordinator.state.live?.slide.elements[1] else { return XCTFail("No verse text") }
        XCTAssertEqual(verse.style, theme.body.style)
        XCTAssertEqual(verse.box, theme.body.box)
        XCTAssertEqual(verse.overrides, [])
    }

    func testNextStepsThroughThePagesThenCarriesOnWithTheShow() throws {
        let f = makeFixture()
        try showOverSermon(f)
        XCTAssertEqual(texts(f.coordinator.upNextSlide?.slide).last, "John 3:17 · KJV")

        XCTAssertEqual(f.coordinator.nextSlide(), .applied)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide).last, "John 3:17 · KJV")
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.sermon))
        XCTAssertEqual(f.coordinator.nextSlide(), .applied)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide).last, "John 3:18 · KJV")
        // The last page: up next is the slide after the sermon.
        XCTAssertEqual(texts(f.coordinator.upNextSlide?.slide), ["Offering"])

        XCTAssertEqual(f.coordinator.nextSlide(), .applied)
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.after))
        XCTAssertEqual(texts(f.coordinator.state.live?.slide), ["Offering"])
        XCTAssertNil(f.coordinator.state.scriptureOverlay)
    }

    func testPreviousOnTheFirstPageGoesToTheSlideBefore() throws {
        let f = makeFixture()
        try showOverSermon(f)
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.previousSlide(), .applied)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide).last, "John 3:16 · KJV")

        XCTAssertEqual(f.coordinator.previousSlide(), .applied)
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.before))
        XCTAssertNil(f.coordinator.state.scriptureOverlay)
    }

    func testEachPageIsANewSlideSoItTransitions() throws {
        let f = makeFixture()
        try showOverSermon(f)
        let first = f.coordinator.state.live?.slide.id
        f.coordinator.nextSlide()
        XCTAssertNotEqual(f.coordinator.state.live?.slide.id, first)
        XCTAssertNotEqual(f.coordinator.state.live?.slide.id, f.sermon.id)
    }

    func testTakingAnotherSlideLiveEndsTheVerses() throws {
        let f = makeFixture()
        try showOverSermon(f)
        f.coordinator.takeLive(slideID: f.after.id, inItem: f.item.id)
        XCTAssertNil(f.coordinator.state.scriptureOverlay)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide), ["Offering"])
    }

    func testEndScriptureLeavesTheSlideOnItsOwn() throws {
        let f = makeFixture()
        try showOverSermon(f)
        XCTAssertEqual(f.coordinator.endScripture(), .applied)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide), ["The Good News"])
        XCTAssertNil(f.coordinator.state.scriptureOverlay)
        XCTAssertEqual(f.coordinator.endScripture(), .rejected(.nothingLive))
    }

    func testClearAndRestoreKeepThePage() throws {
        let f = makeFixture()
        try showOverSermon(f)
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.clearOutput(), .applied)
        XCTAssertNil(f.coordinator.state.scriptureOverlay)

        XCTAssertEqual(f.coordinator.restoreOutput(), .applied)
        XCTAssertEqual(texts(f.coordinator.state.live?.slide).last, "John 3:17 · KJV")
        XCTAssertNil(f.coordinator.state.autoAdvance)
        f.coordinator.nextSlide()
        XCTAssertEqual(texts(f.coordinator.state.live?.slide).last, "John 3:18 · KJV")
    }

    func testTheCuedSlidesCountdownDoesNotTakeTheVersesAway() throws {
        let f = makeFixture()
        try showOverSermon(f)
        XCTAssertNil(f.coordinator.state.autoAdvance)
        XCTAssertFalse(f.coordinator.advanceIfDue())
    }

    func testEditingTheSlideUnderneathCountsAsPending() throws {
        let f = makeFixture()
        try showOverSermon(f)
        let presentationID = f.coordinator.project.presentations[0].id
        f.coordinator.setSlideBackground(.color(.black), slideID: f.sermon.id, inPresentation: presentationID)
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)
    }

    func testPreviewDrawsThePagesOverTheCuedSlide() throws {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.scripturePreview(try passage("John 3:16-18"), options: onePerSlide, themeID: nil), [])
        f.coordinator.cueSlide(f.sermon.id, inItem: f.item.id)
        let pages = f.coordinator.scripturePreview(try passage("John 3:16-18"), options: onePerSlide, themeID: nil)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map { texts($0.slide).first }, Array(repeating: "The Good News", count: 3))
        XCTAssertEqual(pages.first?.background, sermonBackground)
        XCTAssertNil(f.coordinator.state.live, "Previewing shows nothing")
    }
}
