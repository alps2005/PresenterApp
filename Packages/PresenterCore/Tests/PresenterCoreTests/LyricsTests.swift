import Foundation
import XCTest
@testable import PresenterCore

final class LyricsTests: XCTestCase {
    func testBlankLinesSplitSlidesAndSectionNamesLabelThem() {
        let lyrics = """
        Verse 1
        Amazing grace how sweet the sound
        That saved a wretch like me

        I once was lost but now am found
        Was blind but now I see

        [Chorus]:
        My chains are gone
        I've been set free
        """
        let slides = LyricsParser.slides(from: lyrics)

        XCTAssertEqual(slides.map(\.primaryText), [
            "Amazing grace how sweet the sound\nThat saved a wretch like me",
            "I once was lost but now am found\nWas blind but now I see",
            "My chains are gone\nI've been set free",
        ])
        XCTAssertEqual(slides.map(\.label), ["Verse 1", "Verse 1", "Chorus"])
    }

    func testSpanishSectionNamesAndWindowsLineEndings() {
        let slides = LyricsParser.slides(from: "CORO:\r\nCuán grande es Él\r\n\r\nPuente\r\nSanto, santo")
        XCTAssertEqual(slides.map(\.label), ["Coro", "Puente"])
        XCTAssertEqual(slides.map(\.primaryText), ["Cuán grande es Él", "Santo, santo"])
    }

    func testLongStanzasSplitByMaximumLines() {
        let slides = LyricsParser.slides(from: "a\nb\nc\nd\ne", maxLinesPerSlide: 2)
        XCTAssertEqual(slides.map(\.primaryText), ["a\nb", "c\nd", "e"])
    }

    func testOrdinaryLinesAreNotMistakenForSectionNames() {
        XCTAssertNil(LyricsParser.sectionLabel("Chorus of angels sing"))
        XCTAssertNil(LyricsParser.sectionLabel("Verse"  + " by verse we grow"))
        XCTAssertEqual(LyricsParser.sectionLabel("pre-chorus 2"), "Pre-Chorus 2")
        XCTAssertEqual(LyricsParser.sectionLabel("(Bridge)"), "Bridge")
    }

    func testEmptyLyricsGiveNoSlides() {
        XCTAssertEqual(LyricsParser.slides(from: "  \n\n Chorus \n"), [])
    }

    func testSectionKinds() {
        XCTAssertEqual(SongSectionKind(label: "Verse 2"), .verse)
        XCTAssertEqual(SongSectionKind(label: "Coro"), .chorus)
        XCTAssertEqual(SongSectionKind(label: "Pre-Chorus"), .preChorus)
        XCTAssertEqual(SongSectionKind(label: "Puente"), .bridge)
        XCTAssertEqual(SongSectionKind(label: "Tag"), .tag)
        XCTAssertEqual(SongSectionKind(label: "Notes"), .other)
    }

    @MainActor
    func testAddSongCreatesSelectedPlaylistItemAndIsUndoable() {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T"))

        let item = coordinator.addSong(title: "Grace", lyrics: "Verse\nLine one\n\nChorus\nLine two")

        XCTAssertEqual(coordinator.state.selectedItemID, item?.id)
        let presentation = coordinator.project.presentation(forItem: item!.id)
        XCTAssertEqual(presentation?.title, "Grace")
        XCTAssertEqual(presentation?.slides.map(\.label), ["Verse", "Chorus"])
        XCTAssertEqual(presentation?.kind, .song)
        XCTAssertNil(coordinator.addSong(title: "Empty", lyrics: "\n\n"))

        coordinator.undo()
        XCTAssertTrue(coordinator.project.playlist.items.isEmpty)
    }

    @MainActor
    func testSetLabelTrimsAndClears() {
        let presentation = PresentationDocument(title: "P", slides: [.text("x")])
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T", presentations: [presentation]))
        let slideID = presentation.slides[0].id

        coordinator.setLabel("  Tag ", slideID: slideID, inPresentation: presentation.id)
        XCTAssertEqual(coordinator.project.presentation(withID: presentation.id)?.slides[0].label, "Tag")
        coordinator.setLabel("", slideID: slideID, inPresentation: presentation.id)
        XCTAssertNil(coordinator.project.presentation(withID: presentation.id)?.slides[0].label)
    }
}
