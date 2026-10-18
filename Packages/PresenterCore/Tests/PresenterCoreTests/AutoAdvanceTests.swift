import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class AutoAdvanceTests: XCTestCase {
    /// Two items: A (slides a1, a2, a3) and B (slide b1), with a clock the test moves.
    @MainActor
    private final class Fixture {
        var clock = Date(timeIntervalSince1970: 1000)
        let coordinator: PresentationCoordinator
        let itemA: PresentationItem
        let itemB: PresentationItem
        let presentationA: PresentationDocument
        let a1: SlideDocument, a2: SlideDocument, a3: SlideDocument, b1: SlideDocument

        init(a1: SlideDocument = .text("A1"), a2: SlideDocument = .text("A2"), a3: SlideDocument = .text("A3")) {
            self.a1 = a1; self.a2 = a2; self.a3 = a3
            b1 = .text("B1")
            presentationA = PresentationDocument(title: "A", slides: [a1, a2, a3])
            let presentationB = PresentationDocument(title: "B", slides: [b1])
            itemA = PresentationItem(presentationID: presentationA.id)
            itemB = PresentationItem(presentationID: presentationB.id)
            coordinator = PresentationCoordinator(project: ProjectDocument(
                name: "Test",
                presentations: [presentationA, presentationB],
                playlist: PlaylistDocument(title: "P", items: [itemA, itemB])
            ))
            coordinator.now = { [unowned self] in clock }
        }

        var liveSlideID: UUID? { coordinator.state.live?.position.slideID }

        /// Moves the clock on and lets a due countdown fire, as the app's driver does.
        @discardableResult
        func wait(_ seconds: TimeInterval) -> Bool {
            clock += seconds
            return coordinator.advanceIfDue()
        }
    }

    func testSlideshowLoopsWithinItsPresentation() {
        let f = Fixture()
        f.coordinator.setSlideshowInterval(5, presentation: f.presentationA.id)
        f.coordinator.takeLive(slideID: f.a2.id, inItem: f.itemA.id)

        XCTAssertFalse(f.wait(4.9))
        XCTAssertEqual(f.liveSlideID, f.a2.id)
        XCTAssertTrue(f.wait(0.1))
        XCTAssertEqual(f.liveSlideID, f.a3.id)
        f.wait(5)
        XCTAssertEqual(f.liveSlideID, f.a1.id, "After the last slide, a Slideshow goes back to the first")
        XCTAssertEqual(f.coordinator.state.live?.position.itemID, f.itemA.id)
    }

    func testSlideTimerOverridesTheSlideshow() {
        let f = Fixture(a1: SlideDocument(elements: [], goToNext: GoToNextTimer(seconds: 2)))
        f.coordinator.setSlideshowInterval(10, presentation: f.presentationA.id)
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        f.wait(2)
        XCTAssertEqual(f.liveSlideID, f.a2.id)
        XCTAssertFalse(f.wait(9), "a2 has no timer of its own, so it waits the Slideshow's 10 seconds")
        XCTAssertTrue(f.wait(1))
        XCTAssertEqual(f.liveSlideID, f.a3.id)
    }

    func testGoToNextMovesIntoTheNextItemAndStopsAtTheEndOfTheShow() {
        let f = Fixture(a3: SlideDocument(elements: [], goToNext: GoToNextTimer(seconds: 3)))
        f.coordinator.takeLive(slideID: f.a3.id, inItem: f.itemA.id)

        f.wait(3)
        XCTAssertEqual(f.coordinator.state.live?.position, SlidePosition(itemID: f.itemB.id, slideID: f.b1.id))
        XCTAssertNil(f.coordinator.state.autoAdvance, "b1 has no timer")

        f.coordinator.setGoToNext(GoToNextTimer(seconds: 1), forSlides: [f.b1.id], inPresentation: f.coordinator.project.presentations[1].id)
        XCTAssertNotNil(f.coordinator.state.autoAdvance, "Giving the live slide a timer starts it")
        XCTAssertFalse(f.wait(1), "Nothing comes after the last slide of the show")
        XCTAssertEqual(f.liveSlideID, f.b1.id)
        XCTAssertNil(f.coordinator.state.autoAdvance)
        XCTAssertNil(f.coordinator.lastRejection, "Running out of slides isn't an error to show the operator")
    }

    func testLoopToFirstSlide() {
        let f = Fixture(a3: SlideDocument(elements: [], goToNext: GoToNextTimer(seconds: 1, loopsToFirst: true)))
        f.coordinator.takeLive(slideID: f.a3.id, inItem: f.itemA.id)
        f.wait(1)
        XCTAssertEqual(f.liveSlideID, f.a1.id)
    }

    func testManualNextRestartsTheCountdown() {
        let f = Fixture()
        f.coordinator.setSlideshowInterval(5, presentation: f.presentationA.id)
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        f.clock += 4
        f.coordinator.nextSlide()
        XCTAssertEqual(f.liveSlideID, f.a2.id)
        XCTAssertFalse(f.wait(4), "→ starts a new 5-second countdown for a2")
        XCTAssertTrue(f.wait(1))
        XCTAssertEqual(f.liveSlideID, f.a3.id)
    }

    func testClearBlackoutAndStopEndTheCountdownAndRestoreStartsItAgain() {
        let f = Fixture()
        f.coordinator.setSlideshowInterval(5, presentation: f.presentationA.id)
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        f.coordinator.blackout()
        XCTAssertNil(f.coordinator.state.autoAdvance)
        XCTAssertFalse(f.wait(10))
        f.coordinator.restoreOutput()
        XCTAssertFalse(f.wait(4.9), "Restore starts a full countdown")
        XCTAssertTrue(f.wait(0.1))
        XCTAssertEqual(f.liveSlideID, f.a2.id)

        f.coordinator.clearOutput()
        XCTAssertNil(f.coordinator.state.autoAdvance)

        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        XCTAssertEqual(f.coordinator.stopAutoAdvance(), .applied)
        XCTAssertFalse(f.wait(10))
        XCTAssertEqual(f.liveSlideID, f.a1.id)
        XCTAssertEqual(f.coordinator.stopAutoAdvance(), .rejected(.autoAdvanceOff))
    }

    func testAVideoPlayingOnceHoldsTheCountdownUntilItEnds() {
        let video = UUID()
        let f = Fixture(a1: SlideDocument(
            elements: [],
            background: .video(VideoBackground(assetID: video, loops: false)),
            goToNext: GoToNextTimer(seconds: 0)
        ))
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        XCTAssertEqual(f.coordinator.state.autoAdvance?.phase, .waitingForVideo(assetID: video))
        XCTAssertFalse(f.wait(60))

        f.coordinator.videoDidFinish(UUID())
        XCTAssertFalse(f.wait(1), "Another video ending changes nothing")
        f.coordinator.videoDidFinish(video)
        XCTAssertTrue(f.wait(PresentationCoordinator.minimumAdvanceDelay), "0 seconds moves on as the video ends")
        XCTAssertEqual(f.liveSlideID, f.a2.id)
    }

    func testALoopingVideoDoesntHoldTheCountdown() {
        let f = Fixture(a1: SlideDocument(
            elements: [],
            background: .video(VideoBackground(assetID: UUID(), loops: true)),
            goToNext: GoToNextTimer(seconds: 5)
        ))
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        XCTAssertTrue(f.wait(5))
        XCTAssertEqual(f.liveSlideID, f.a2.id)
    }

    func testCountdownProgress() {
        let f = Fixture()
        f.coordinator.setSlideshowInterval(4, presentation: f.presentationA.id)
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        let advance = try! XCTUnwrap(f.coordinator.state.autoAdvance)
        XCTAssertEqual(advance.progress(at: f.clock + 1), 0.25)
        XCTAssertEqual(advance.secondsLeft(at: f.clock + 1.5), 3)
        XCTAssertEqual(advance.progress(at: f.clock + 10), 1)
    }

    func testEditingTimersIsUndoableAndClamped() {
        let f = Fixture()
        f.coordinator.setSlideshowInterval(0.2, presentation: f.presentationA.id)
        XCTAssertEqual(f.coordinator.project.presentations[0].slideshowInterval, PresentationCoordinator.minimumSlideshowInterval)
        f.coordinator.setGoToNext(GoToNextTimer(seconds: -3), forSlides: [f.a1.id, f.a2.id], inPresentation: f.presentationA.id)
        XCTAssertEqual(f.coordinator.project.presentations[0].slides.map(\.goToNext?.seconds), [0, 0, nil])
        XCTAssertEqual(f.coordinator.setGoToNext(nil, forSlides: [UUID()], inPresentation: f.presentationA.id), .rejected(.unknownSlide))

        f.coordinator.undo()
        XCTAssertEqual(f.coordinator.project.presentations[0].slides.map(\.goToNext), [nil, nil, nil])
        f.coordinator.undo()
        XCTAssertNil(f.coordinator.project.presentations[0].slideshowInterval)
    }

    func testTimersRoundTripAndVersionThreeFilesLoadWithout() throws {
        let f = Fixture(a1: SlideDocument(elements: [], goToNext: GoToNextTimer(seconds: 8, loopsToFirst: true)))
        f.coordinator.setSlideshowInterval(5, presentation: f.presentationA.id)
        let project = f.coordinator.project
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(project)), project)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any]
        json["schemaVersion"] = 3
        var presentations = json["presentations"] as! [[String: Any]]
        presentations[0].removeValue(forKey: "slideshowInterval")
        var slides = presentations[0]["slides"] as! [[String: Any]]
        slides[0].removeValue(forKey: "goToNext")
        presentations[0]["slides"] = slides
        json["presentations"] = presentations
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.presentations[0].slideshowInterval)
        XCTAssertNil(decoded.presentations[0].slides[0].goToNext)
    }
}
