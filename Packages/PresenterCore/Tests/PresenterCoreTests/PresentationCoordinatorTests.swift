import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class PresentationCoordinatorTests: XCTestCase {
    /// Two items: A (slides a1, a2) and B (slide b1).
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let itemA: PresentationItem
        let itemB: PresentationItem
        let a1: SlideDocument
        let a2: SlideDocument
        let b1: SlideDocument
        let presentationA: PresentationDocument

        func position(_ item: PresentationItem, _ slide: SlideDocument) -> SlidePosition {
            SlidePosition(itemID: item.id, slideID: slide.id)
        }
    }

    private func makeFixture() -> Fixture {
        let a1 = SlideDocument.text("A1")
        let a2 = SlideDocument.text("A2")
        let b1 = SlideDocument.text("B1")
        let presentationA = PresentationDocument(title: "A", slides: [a1, a2])
        let presentationB = PresentationDocument(title: "B", slides: [b1])
        let itemA = PresentationItem(presentationID: presentationA.id)
        let itemB = PresentationItem(presentationID: presentationB.id)
        let project = ProjectDocument(
            name: "Test",
            presentations: [presentationA, presentationB],
            playlist: PlaylistDocument(title: "P", items: [itemA, itemB])
        )
        return Fixture(
            coordinator: PresentationCoordinator(project: project),
            itemA: itemA, itemB: itemB, a1: a1, a2: a2, b1: b1, presentationA: presentationA
        )
    }

    // MARK: Selection vs preview vs live

    func testInitialStateSelectsFirstItemAndNothingIsLive() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.state.selectedItemID, f.itemA.id)
        XCTAssertNil(f.coordinator.state.preview)
        XCTAssertNil(f.coordinator.state.live)
        XCTAssertEqual(f.coordinator.audienceScene, .empty)
    }

    func testSelectingItemDoesNotChangeLive() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        let liveBefore = f.coordinator.state.live

        XCTAssertEqual(f.coordinator.selectItem(f.itemB.id), .applied)

        XCTAssertEqual(f.coordinator.state.selectedItemID, f.itemB.id)
        XCTAssertEqual(f.coordinator.state.live, liveBefore)
    }

    func testCueingSlideDoesNotTakeItLive() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.cueSlide(f.a2.id, inItem: f.itemA.id), .applied)

        XCTAssertEqual(f.coordinator.state.preview, f.position(f.itemA, f.a2))
        XCTAssertNil(f.coordinator.state.live)
        XCTAssertEqual(f.coordinator.audienceScene, .empty)
    }

    func testTakeLiveSendsCuedSlideToAudience() {
        let f = makeFixture()
        f.coordinator.cueSlide(f.a2.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.takeLive(), .applied)

        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemA, f.a2))
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.a2)))
    }

    func testTakeLiveWithNothingCuedIsRejected() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.takeLive(), .rejected(.nothingCued))
        XCTAssertEqual(f.coordinator.lastRejection, .nothingCued)
        XCTAssertNil(f.coordinator.state.live)
    }

    func testCueingUnknownSlideIsRejected() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.cueSlide(UUID(), inItem: f.itemA.id), .rejected(.unknownSlide))
        XCTAssertEqual(f.coordinator.cueSlide(f.a1.id, inItem: UUID()), .rejected(.unknownItem))
        XCTAssertEqual(f.coordinator.cueSlide(f.b1.id, inItem: f.itemA.id), .rejected(.unknownSlide))
        XCTAssertNil(f.coordinator.state.preview)
    }

    // MARK: Navigation

    func testNextAndPreviousCrossPlaylistItems() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.upNextPosition, f.position(f.itemA, f.a2))
        XCTAssertEqual(f.coordinator.nextSlide(), .applied)
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemA, f.a2))
        XCTAssertEqual(f.coordinator.nextSlide(), .applied)
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemB, f.b1))

        XCTAssertEqual(f.coordinator.previousSlide(), .applied)
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemA, f.a2))
    }

    func testNextAtEndOfPlaylistStaysOnLastSlide() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.b1.id, inItem: f.itemB.id)

        XCTAssertNil(f.coordinator.upNextPosition)
        XCTAssertEqual(f.coordinator.nextSlide(), .rejected(.atEndOfPlaylist))
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemB, f.b1))
    }

    func testPreviousAtStartOfPlaylistStaysOnFirstSlide() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.previousSlide(), .rejected(.atStartOfPlaylist))
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemA, f.a1))
    }

    func testNavigationWithNothingLiveIsRejected() {
        let f = makeFixture()
        f.coordinator.cueSlide(f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.nextSlide(), .rejected(.nothingLive))
        XCTAssertEqual(f.coordinator.previousSlide(), .rejected(.nothingLive))
        XCTAssertNil(f.coordinator.state.live)
    }

    func testNavigationDoesNotMovePreview() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.state.preview, f.position(f.itemA, f.a1))
    }

    func testSamePresentationTwiceInPlaylistIsNavigatedAsSeparateItems() {
        let f = makeFixture()
        let again = PresentationItem(presentationID: f.presentationA.id)
        let project = ProjectDocument(
            name: "Repeat",
            presentations: [f.presentationA],
            playlist: PlaylistDocument(title: "P", items: [f.itemA, again])
        )
        let coordinator = PresentationCoordinator(project: project)
        coordinator.takeLive(slideID: f.a2.id, inItem: f.itemA.id)

        XCTAssertEqual(coordinator.nextSlide(), .applied)
        XCTAssertEqual(coordinator.state.live?.position, SlidePosition(itemID: again.id, slideID: f.a1.id))
    }

    // MARK: Clear, blackout, restore

    func testClearRemovesLiveSlideAndRestoreBringsItBack() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.clearOutput(), .applied)
        XCTAssertNil(f.coordinator.state.live)
        XCTAssertEqual(f.coordinator.audienceScene, .empty)

        XCTAssertEqual(f.coordinator.restoreOutput(), .applied)
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.a1)))
    }

    func testClearWithNothingLiveIsRejected() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.clearOutput(), .rejected(.nothingLive))
    }

    func testBlackoutOverridesLiveSlideUntilRestored() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        f.coordinator.blackout()
        XCTAssertEqual(f.coordinator.audienceScene, .black)

        // Navigating during blackout moves live underneath but keeps the output black.
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.state.live?.position, f.position(f.itemA, f.a2))
        XCTAssertEqual(f.coordinator.audienceScene, .black)

        XCTAssertEqual(f.coordinator.restoreOutput(), .applied)
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.a2)))
    }

    func testRestoreWithNothingToRestoreIsRejected() {
        let f = makeFixture()
        XCTAssertFalse(f.coordinator.canRestore)
        XCTAssertEqual(f.coordinator.restoreOutput(), .rejected(.nothingToRestore))
    }

    func testTakingLiveAfterClearDiscardsClearedSlide() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)
        f.coordinator.clearOutput()
        f.coordinator.takeLive(slideID: f.b1.id, inItem: f.itemB.id)

        XCTAssertNil(f.coordinator.state.cleared)
        XCTAssertEqual(f.coordinator.restoreOutput(), .rejected(.nothingToRestore))
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.b1)))
    }

    // MARK: Editing never leaks to live

    func testEditingLiveSlideDoesNotChangeAudienceUntilRetaken() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        f.coordinator.updateSlideText("Edited", slideID: f.a1.id, inPresentation: f.presentationA.id)

        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.a1)))
        XCTAssertEqual(f.coordinator.project.slide(at: f.position(f.itemA, f.a1))?.plainText, "Edited")
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)

        f.coordinator.takeLive()
        XCTAssertEqual(f.coordinator.state.live?.slide.plainText, "Edited")
        XCTAssertFalse(f.coordinator.liveSlideHasPendingEdits)
    }

    func testDeletingLiveSlideKeepsOutputAndRejectsNavigation() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.deleteSlide(f.a1.id, inPresentation: f.presentationA.id), .applied)

        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.a1)))
        XCTAssertNil(f.coordinator.state.preview)
        XCTAssertEqual(f.coordinator.nextSlide(), .rejected(.liveSlideMissing))
    }

    func testAddSlideInsertsAfterCuedSlideAndCuesIt() {
        let f = makeFixture()
        f.coordinator.cueSlide(f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.addSlide(toItem: f.itemA.id), .applied)

        let slides = f.coordinator.project.presentation(withID: f.presentationA.id)!.slides
        XCTAssertEqual(slides.count, 3)
        XCTAssertEqual(slides[0].id, f.a1.id)
        XCTAssertEqual(slides[2].id, f.a2.id)
        XCTAssertEqual(f.coordinator.state.preview, SlidePosition(itemID: f.itemA.id, slideID: slides[1].id))
        XCTAssertNil(f.coordinator.state.live)
    }

    func testAddPresentationAppendsToPlaylistAndCuesBlankSlide() {
        let f = makeFixture()
        let item = f.coordinator.addPresentation(title: "New")

        XCTAssertEqual(f.coordinator.project.playlist.items.last, item)
        XCTAssertEqual(f.coordinator.state.selectedItemID, item.id)
        XCTAssertEqual(f.coordinator.previewSlide?.slide.plainText, "")
        XCTAssertNil(f.coordinator.state.live)
    }

    func testRemovingSelectedItemSelectsNeighbour() {
        let f = makeFixture()
        f.coordinator.cueSlide(f.a1.id, inItem: f.itemA.id)

        XCTAssertEqual(f.coordinator.removeItem(f.itemA.id), .applied)

        XCTAssertEqual(f.coordinator.state.selectedItemID, f.itemB.id)
        XCTAssertNil(f.coordinator.state.preview)
    }

    func testMoveItemsReordersPlaylist() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.moveItems(fromOffsets: IndexSet(integer: 1), toOffset: 0), .applied)
        XCTAssertEqual(f.coordinator.project.playlist.items.map(\.id), [f.itemB.id, f.itemA.id])

        XCTAssertEqual(f.coordinator.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 2), .applied)
        XCTAssertEqual(f.coordinator.project.playlist.items.map(\.id), [f.itemA.id, f.itemB.id])

        XCTAssertEqual(f.coordinator.moveItems(fromOffsets: IndexSet(integer: 5), toOffset: 0), .rejected(.unknownItem))
    }
}
