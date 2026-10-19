import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class ShowTests: XCTestCase {
    /// Two presentations in the library; the open show, "Sunday", plays both.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let a: PresentationDocument
        let b: PresentationDocument
        let sunday: PlaylistDocument
    }

    private func makeFixture() -> Fixture {
        let a = PresentationDocument(title: "A", slides: [.text("a1"), .text("a2")])
        let b = PresentationDocument(title: "B", slides: [.text("b1")])
        let sunday = PlaylistDocument(title: "Sunday", items: [PresentationItem(presentationID: a.id),
                                                               PresentationItem(presentationID: b.id)])
        let project = ProjectDocument(name: "Test", presentations: [a, b], playlist: sunday)
        let coordinator = PresentationCoordinator(project: project)
        var clock = Date(timeIntervalSince1970: 1_000)
        coordinator.now = {
            clock += 1
            return clock
        }
        return Fixture(coordinator: coordinator, a: a, b: b, sunday: sunday)
    }

    func testAddPlaylistOpensAnEmptyShowAndKeepsTheLibrary() {
        let f = makeFixture()
        let c = f.coordinator
        c.renamePlaylist(to: "Sunday AM")
        XCTAssertTrue(c.canUndo)

        let wednesday = c.addPlaylist(title: " Wednesday ")
        XCTAssertEqual(c.project.playlists.map(\.title), ["Sunday AM", "Wednesday"])
        XCTAssertEqual(c.project.activePlaylistID, wednesday.id)
        XCTAssertEqual(c.project.playlist.id, wednesday.id)
        XCTAssertTrue(c.project.playlist.items.isEmpty)
        XCTAssertNotNil(c.project.playlist.lastOpenedAt)
        XCTAssertEqual(c.project.presentations.count, 2)
        XCTAssertNil(c.state.selectedItemID)
        XCTAssertFalse(c.canUndo, "Undo can't reach into the show that was open")

        XCTAssertEqual(c.addPlaylist(title: "").title, "Untitled Show")
    }

    func testCommandsWorkOnTheOpenShow() throws {
        let f = makeFixture()
        let c = f.coordinator
        c.addPlaylist(title: "Wednesday")
        let item = try XCTUnwrap(c.addToPlaylist(f.b.id))
        c.addSong(title: "New", lyrics: "Words")

        XCTAssertEqual(c.project.playlist.items.count, 2)
        XCTAssertEqual(c.project.playlist.items.first, item)
        XCTAssertEqual(c.project.playlist(withID: f.sunday.id)?.items, f.sunday.items, "Sunday is untouched")
        XCTAssertEqual(c.project.presentations.count, 3, "The song is in the shared library")
    }

    func testOpeningAShowKeepsWhatsLiveAndWaitsForATake() throws {
        let f = makeFixture()
        let c = f.coordinator
        let first = f.sunday.items[0]
        XCTAssertEqual(c.takeLive(slideID: f.a.slides[0].id, inItem: first.id), .applied)
        let live = c.state.live

        let wednesday = c.addPlaylist(title: "Wednesday")
        XCTAssertEqual(c.state.live, live)
        XCTAssertEqual(c.nextSlide(), .rejected(.liveSlideMissing))

        // Back in Sunday, the live slide is in the show again, so Next carries on.
        XCTAssertEqual(c.openPlaylist(f.sunday.id), .applied)
        XCTAssertEqual(c.state.selectedItemID, first.id)
        XCTAssertEqual(c.nextSlide(), .applied)
        XCTAssertEqual(c.state.live?.position.slideID, f.a.slides[1].id)
        XCTAssertGreaterThan(try XCTUnwrap(c.project.playlist.lastOpenedAt),
                             try XCTUnwrap(c.project.playlist(withID: wednesday.id)?.lastOpenedAt))
        XCTAssertEqual(c.openPlaylist(UUID()), .rejected(.unknownShow))
    }

    func testDuplicateCopiesItemsWithNewIDsAndUndoes() throws {
        let f = makeFixture()
        let c = f.coordinator
        let copy = try XCTUnwrap(c.duplicatePlaylist(f.sunday.id))

        XCTAssertEqual(copy.title, "Sunday Copy")
        XCTAssertEqual(copy.items.map(\.presentationID), [f.a.id, f.b.id])
        XCTAssertTrue(Set(copy.items.map(\.id)).isDisjoint(with: f.sunday.items.map(\.id)))
        XCTAssertEqual(c.project.playlists.map(\.id), [f.sunday.id, copy.id])
        XCTAssertEqual(c.project.activePlaylistID, f.sunday.id, "The open show stays open")
        XCTAssertEqual(c.project.presentations.count, 2, "Presentations are shared, not copied")

        c.undo()
        XCTAssertEqual(c.project.playlists.map(\.id), [f.sunday.id])
        XCTAssertNil(c.duplicatePlaylist(UUID()))
        XCTAssertEqual(c.lastRejection, .unknownShow)
    }

    func testRenameAShowThatIsntOpen() throws {
        let f = makeFixture()
        let c = f.coordinator
        let copy = try XCTUnwrap(c.duplicatePlaylist(f.sunday.id))
        XCTAssertEqual(c.renamePlaylist(copy.id, to: "Easter"), .applied)
        XCTAssertEqual(c.project.playlist(withID: copy.id)?.title, "Easter")
        XCTAssertEqual(c.project.playlist.title, "Sunday")
        XCTAssertEqual(c.renamePlaylist(UUID(), to: "X"), .rejected(.unknownShow))
    }

    func testDeletingAnotherShowUndoes() throws {
        let f = makeFixture()
        let c = f.coordinator
        let copy = try XCTUnwrap(c.duplicatePlaylist(f.sunday.id))
        XCTAssertEqual(c.deletePlaylist(copy.id), .applied)
        XCTAssertEqual(c.project.playlists.map(\.id), [f.sunday.id])
        XCTAssertEqual(c.project.presentations.count, 2, "The library keeps its presentations")
        c.undo()
        XCTAssertEqual(c.project.playlists.map(\.id), [f.sunday.id, copy.id])
    }

    func testDeletingTheOpenShowOpensTheMostRecentOne() {
        let f = makeFixture()
        let c = f.coordinator
        let easter = c.addPlaylist(title: "Easter")
        let wednesday = c.addPlaylist(title: "Wednesday")
        c.openPlaylist(easter.id)
        c.openPlaylist(wednesday.id)

        XCTAssertEqual(c.deletePlaylist(wednesday.id), .applied)
        XCTAssertEqual(c.project.activePlaylistID, easter.id)
        XCTAssertEqual(c.project.playlists.map(\.id), [f.sunday.id, easter.id])
        XCTAssertFalse(c.canUndo)
    }

    func testTheLastShowCantBeDeleted() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.deletePlaylist(f.sunday.id), .rejected(.lastShow))
        XCTAssertEqual(f.coordinator.deletePlaylist(UUID()), .rejected(.unknownShow))
        XCTAssertEqual(f.coordinator.project.playlists.count, 1)
    }

    func testDeletingAPresentationRemovesItFromEveryShow() throws {
        let f = makeFixture()
        let c = f.coordinator
        let copy = try XCTUnwrap(c.duplicatePlaylist(f.sunday.id))
        XCTAssertEqual(c.deletePresentation(f.a.id), .applied)
        XCTAssertEqual(c.project.playlist.items.map(\.presentationID), [f.b.id])
        XCTAssertEqual(c.project.playlist(withID: copy.id)?.items.map(\.presentationID), [f.b.id])
    }

    func testShowsRoundTripAndOlderFilesHaveOne() throws {
        let f = makeFixture()
        let c = f.coordinator
        let wednesday = c.addPlaylist(title: "Wednesday")
        let data = try JSONEncoder().encode(c.project)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(decoded, c.project)
        XCTAssertEqual(decoded.activePlaylistID, wednesday.id)

        // A format 4 file has one "playlist" and no "playlists".
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["schemaVersion"] = 4
        old["playlist"] = (old["playlists"] as? [Any])?.first
        old["playlists"] = nil
        old["activePlaylistID"] = nil
        let legacy = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.playlists.map(\.id), [f.sunday.id])
        XCTAssertEqual(legacy.playlist.items, f.sunday.items)
        XCTAssertEqual(legacy.activePlaylistID, f.sunday.id)

        // An open show that's missing falls back to the first.
        var stray = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        stray["activePlaylistID"] = UUID().uuidString
        let fallback = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: stray))
        XCTAssertEqual(fallback.activePlaylistID, f.sunday.id)
    }
}
