import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class ServiceActivityTests: XCTestCase {
    private func makeCoordinator() -> (PresentationCoordinator, PresentationDocument, PresentationItem) {
        var project = ProjectDocument(name: "T", presentations: [], playlist: PlaylistDocument(title: "S"))
        let song = PresentationDocument(title: "Song", slides: [.text("a")])
        let item = PresentationItem(presentationID: song.id)
        project.presentations = [song]
        project.playlist.items = [item]
        return (PresentationCoordinator(project: project), song, item)
    }

    func testNothingLiveAndNoOutputsIsNotPresenting() {
        let (c, _, _) = makeCoordinator()
        XCTAssertFalse(c.state.isPresenting(outputsShowing: false))
    }

    func testAnOutputOnScreenCountsEvenWithNothingLive() {
        let (c, _, _) = makeCoordinator()
        XCTAssertTrue(c.state.isPresenting(outputsShowing: true))
    }

    func testEachKindOfLiveContentCounts() {
        let (c, song, item) = makeCoordinator()
        c.takeLive(slideID: song.slides[0].id, inItem: item.id)
        XCTAssertTrue(c.state.isPresenting(outputsShowing: false), "A live slide")
        c.clearAll()
        XCTAssertFalse(c.state.isPresenting(outputsShowing: false), "Cleared")

        c.showMessage(c.project.messages[0].id)
        XCTAssertTrue(c.state.isPresenting(outputsShowing: false), "A message")
        c.clearAll()

        c.showStageMessage("Wrap up")
        XCTAssertTrue(c.state.isPresenting(outputsShowing: false), "A stage message")
        c.hideStageMessage()

        c.blackout()
        XCTAssertTrue(c.state.isPresenting(outputsShowing: false), "Blackout")
    }
}
