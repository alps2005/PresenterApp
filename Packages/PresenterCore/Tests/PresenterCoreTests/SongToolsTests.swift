import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class SongToolsTests: XCTestCase {
    private func makeSong() -> (PresentationCoordinator, PresentationItem, PresentationDocument) {
        func slide(_ text: String, _ label: String) -> SlideDocument {
            var slide = SlideDocument.text(text)
            slide.label = label
            return slide
        }
        var verse1 = slide("V1 line", "Verse 1")
        verse1.background = .color(.black)
        let presentation = PresentationDocument(title: "Song", slides: [
            verse1, slide("C line", "Chorus"), slide("V2 line", "Verse 2"), slide("B line", "Bridge"),
        ])
        let item = PresentationItem(presentationID: presentation.id)
        let coordinator = PresentationCoordinator(project: ProjectDocument(
            name: "T", presentations: [presentation], playlist: PlaylistDocument(title: "P", items: [item])
        ))
        return (coordinator, item, presentation)
    }

    private func presentation(_ c: PresentationCoordinator, _ id: UUID) -> PresentationDocument {
        c.project.presentation(withID: id)!
    }

    // MARK: Reflow

    func testReflowTextRoundTripsThroughTheParser() {
        let (_, _, p) = makeSong()
        let reparsed = LyricsParser.slides(from: p.reflowText)
        XCTAssertEqual(reparsed.map(\.primaryText), p.slides.map(\.primaryText))
        XCTAssertEqual(reparsed.map(\.label), p.slides.map(\.label))
    }

    func testReflowKeepsSlideIdentityAndLookAndAddsOrRemovesAtTheEnd() {
        let (c, _, p) = makeSong()

        c.reflow("Verse 1\nNew first line\n\nChorus\nC line\n\nTag\nExtra one\n\nExtra two", presentationID: p.id)

        let slides = presentation(c, p.id).slides
        XCTAssertEqual(slides.count, 4)
        XCTAssertEqual(slides[0].id, p.slides[0].id)
        XCTAssertEqual(slides[0].primaryText, "New first line")
        XCTAssertEqual(slides[0].background, .color(.black))
        XCTAssertEqual(slides[2].id, p.slides[2].id)
        XCTAssertEqual(slides.map(\.label), ["Verse 1", "Chorus", "Tag", "Tag"])

        c.reflow("Verse 1\nOnly one", presentationID: p.id)
        XCTAssertEqual(presentation(c, p.id).slides.map(\.id), [p.slides[0].id])
    }

    func testNewSlidesFromReflowCopyThePreviousSlidesLook() {
        let (c, _, p) = makeSong()
        c.reflow(p.reflowText + "\n\nBrand new", presentationID: p.id)
        let slides = presentation(c, p.id).slides
        XCTAssertEqual(slides.last?.primaryText, "Brand new")
        XCTAssertEqual(slides.last?.primaryTextElement?.style, slides[3].primaryTextElement?.style)
        XCTAssertEqual(slides.last?.label, "Bridge")
    }

    func testBlankSlidesSurviveReflow() {
        var song = PresentationDocument(title: "S", slides: [.text("A"), .text(""), .text("B")])
        song.slides[1].elements.append(.shape(ShapeElement(kind: .ellipse, frame: .centered(width: 0.2, height: 0.2))))
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T", presentations: [song]))

        coordinator.reflow(song.reflowText, presentationID: song.id)

        let slides = coordinator.project.presentations[0].slides
        XCTAssertEqual(slides.map(\.id), song.slides.map(\.id))
        XCTAssertEqual(slides[1].elements.count, 2)
    }

    func testReflowTypingUndoesInOneStep() {
        let (c, _, p) = makeSong()
        var clock = Date(timeIntervalSince1970: 0)
        c.now = { clock }
        c.reflow(p.reflowText + "\n\nA", presentationID: p.id)
        clock += 0.3
        c.reflow(p.reflowText + "\n\nAB", presentationID: p.id)
        c.undo()
        XCTAssertEqual(presentation(c, p.id).slides.count, 4)
    }

    // MARK: Arrangements

    func testArrangementPlaysRepeatsAsDistinctPositions() {
        let (c, item, p) = makeSong()
        c.addArrangement(name: "Sunday", groups: ["Verse 1", "Chorus", "Verse 2", "Chorus", "Missing"], toPresentation: p.id)
        let chorus = p.slides[1].id

        XCTAssertEqual(presentation(c, p.id).arrangedSlides.map(\.slideID),
                       [p.slides[0].id, chorus, p.slides[2].id, chorus])

        c.takeLive(slideID: p.slides[0].id, inItem: item.id)
        c.nextSlide()
        XCTAssertEqual(c.state.live?.position, SlidePosition(itemID: item.id, slideID: chorus, occurrence: 0))
        c.nextSlide()
        c.nextSlide()
        XCTAssertEqual(c.state.live?.position, SlidePosition(itemID: item.id, slideID: chorus, occurrence: 1))
        XCTAssertEqual(c.nextSlide(), .rejected(.atEndOfPlaylist))
        c.previousSlide()
        XCTAssertEqual(c.state.live?.position.slideID, p.slides[2].id)
    }

    func testSwitchingBackToSlideOrderKeepsNavigationWorking() {
        let (c, item, p) = makeSong()
        let arrangement = c.addArrangement(name: "A", groups: ["Chorus", "Chorus"], toPresentation: p.id)!
        c.takeLive(slideID: p.slides[1].id, inItem: item.id, occurrence: 1)

        c.setActiveArrangement(nil, inPresentation: p.id)

        // The second repeat is gone; Next continues from the chorus's place in slide order.
        XCTAssertEqual(c.nextSlide(), .applied)
        XCTAssertEqual(c.state.live?.position.slideID, p.slides[2].id)
        XCTAssertEqual(c.setActiveArrangement(UUID(), inPresentation: p.id), .rejected(.unknownArrangement))
        XCTAssertEqual(c.deleteArrangement(arrangement.id, inPresentation: p.id), .applied)
        XCTAssertTrue(presentation(c, p.id).arrangements.isEmpty)
    }

    func testCueOfARepeatThatDisappearsIsCleared() {
        let (c, item, p) = makeSong()
        let arrangement = c.addArrangement(name: "A", groups: ["Chorus", "Chorus"], toPresentation: p.id)!
        c.cueSlide(p.slides[1].id, inItem: item.id, occurrence: 1)

        var shorter = arrangement
        shorter.groups = ["Chorus"]
        c.updateArrangement(shorter, inPresentation: p.id)

        XCTAssertNil(c.state.preview)
    }

    func testGroupNamesInFirstAppearanceOrder() {
        let (_, _, p) = makeSong()
        XCTAssertEqual(p.groupNames, ["Verse 1", "Chorus", "Verse 2", "Bridge"])
    }

    // MARK: Library and search

    func testLibraryAddToPlaylistAndDelete() {
        let (c, item, p) = makeSong()
        c.removeItem(item.id)
        XCTAssertNotNil(c.project.presentation(withID: p.id), "removing from the playlist keeps it in the library")

        let added = c.addToPlaylist(p.id)
        XCTAssertEqual(c.state.selectedItemID, added?.id)
        c.addToPlaylist(p.id)
        XCTAssertEqual(c.project.playlist.items.count, 2)

        XCTAssertEqual(c.deletePresentation(p.id), .applied)
        XCTAssertTrue(c.project.playlist.items.isEmpty)
        XCTAssertNil(c.project.presentation(withID: p.id))
        XCTAssertNil(c.addToPlaylist(p.id))
    }

    func testDeletingTheLivePresentationLeavesTheOutputAlone() {
        let (c, item, p) = makeSong()
        c.takeLive(slideID: p.slides[0].id, inItem: item.id)
        let live = c.audienceScene
        c.deletePresentation(p.id)
        XCTAssertEqual(c.audienceScene, live)
    }

    func testSearchMatchesTitleAndWordsIgnoringCaseAndAccents() {
        let p = PresentationDocument(title: "Cuán Grande Es Él", slides: [.text("Señor mi Dios")])
        XCTAssertTrue(p.matches("cuan grande"))
        XCTAssertTrue(p.matches("SENOR"))
        XCTAssertTrue(p.matches(""))
        XCTAssertFalse(p.matches("amazing"))
    }

    func testFilesWithoutArrangementsOrOccurrencesStillLoad() throws {
        let p = PresentationDocument(title: "P", slides: [.text("x")])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json.removeValue(forKey: "arrangements")
        let decoded = try JSONDecoder().decode(PresentationDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.arrangements, [])

        let position = try JSONDecoder().decode(SlidePosition.self, from: Data(#"{"itemID":"\#(UUID())","slideID":"\#(UUID())"}"#.utf8))
        XCTAssertEqual(position.occurrence, 0)
    }
}
