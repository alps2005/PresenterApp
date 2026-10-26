import XCTest
@testable import PresenterCore

@MainActor
final class SectionKeysTests: XCTestCase {
    private let lyrics = """
        Verse 1
        Amazing grace

        Chorus
        My chains are gone
        Line two

        Verse 2
        Twas grace

        Puente
        Bridge words

        Tag
        Last words
        """

    private func makeSong() throws -> (PresentationCoordinator, PresentationItem, PresentationDocument) {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let item = try XCTUnwrap(coordinator.addSong(title: "Grace", lyrics: lyrics, maxLinesPerSlide: 1))
        return (coordinator, item, try XCTUnwrap(coordinator.project.presentation(forItem: item.id)))
    }

    private func liveLabel(_ coordinator: PresentationCoordinator, _ presentation: PresentationDocument) -> String? {
        coordinator.state.live.flatMap { presentation.slide(withID: $0.position.slideID)?.label }
    }

    func testKindsAndHotkeys() {
        XCTAssertEqual(SongSectionKind(label: "Coro 2"), .chorus)
        XCTAssertEqual(SongSectionKind(label: "Estribillo"), .chorus)
        XCTAssertEqual(SongSectionKind(label: "Tag"), .tag)
        XCTAssertEqual(SongSectionKind(label: "Outro"), .ending)
        XCTAssertEqual(SongSectionKind(label: "Final"), .ending)
        XCTAssertEqual(SongSectionKind(label: "Interludio"), .interlude)
        XCTAssertEqual(SongSectionKind(label: "Intro"), .intro)
        XCTAssertEqual(SongSectionKind(label: "Notes"), .other)
        XCTAssertEqual(SongSectionKind(hotkey: "V"), .verse)
        XCTAssertEqual(SongSectionKind(hotkey: "c"), .chorus)
        XCTAssertEqual(SongSectionKind(hotkey: "n"), .interlude)
        XCTAssertNil(SongSectionKind(hotkey: "x"))
        XCTAssertEqual(SongSectionKind.number(inLabel: "Verse 12"), 12)
        XCTAssertEqual(SongSectionKind.number(inLabel: "Coro 2:"), 2)
        XCTAssertNil(SongSectionKind.number(inLabel: "Chorus"))
    }

    func testSectionKeysJumpAndCycle() throws {
        let (c, _, song) = try makeSong()
        XCTAssertEqual(c.sectionCount(.verse), 2)
        XCTAssertEqual(c.sectionCount(.chorus), 1)

        XCTAssertEqual(c.takeLiveSection(.chorus), .applied, "Works on the selected item with nothing live")
        XCTAssertEqual(liveLabel(c, song), "Chorus")
        XCTAssertEqual(c.state.live?.position.slideID, song.slides(inGroup: "Chorus").first?.id, "The section's first slide")

        c.takeLiveSection(.verse)
        XCTAssertEqual(liveLabel(c, song), "Verse 2", "The next verse after the live slide")
        c.takeLiveSection(.verse)
        XCTAssertEqual(liveLabel(c, song), "Verse 1", "Wraps round")
        c.takeLiveSection(.verse, number: 2)
        XCTAssertEqual(liveLabel(c, song), "Verse 2")
        c.takeLiveSection(.bridge)
        XCTAssertEqual(liveLabel(c, song), "Puente", "Spanish labels")
        c.takeLiveSection(.tag)
        XCTAssertEqual(liveLabel(c, song), "Tag")

        XCTAssertEqual(c.takeLiveSection(.preChorus), .rejected(.noSuchSection))
        XCTAssertEqual(c.takeLiveSection(.verse, number: 3), .rejected(.noSuchSection))
        XCTAssertEqual(liveLabel(c, song), "Tag", "A rejected key leaves the output alone")
    }

    func testSectionKeysFollowTheArrangement() throws {
        let (c, _, song) = try makeSong()
        let order = try XCTUnwrap(c.addArrangement(name: "Live", groups: ["Verse 1", "Chorus", "Verse 2", "Chorus"],
                                                   toPresentation: song.id))
        c.setActiveArrangement(order.id, inPresentation: song.id)

        c.takeLiveSection(.chorus)
        XCTAssertEqual(c.state.live?.position.occurrence, 0)
        c.takeLiveSection(.chorus)
        XCTAssertEqual(c.state.live?.position.occurrence, 1, "The chorus's second time through")
        XCTAssertEqual(c.takeLiveSection(.bridge), .rejected(.noSuchSection), "Not in the arrangement")
    }

    func testNumberlessLabelCountsAsOne() throws {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let item = try XCTUnwrap(c.addSong(title: "S", lyrics: "Coro\nA\n\nVerso\nB"))
        let song = try XCTUnwrap(c.project.presentation(forItem: item.id))
        c.takeLiveSection(.verse, number: 1)
        XCTAssertEqual(liveLabel(c, song), "Verso")
        XCTAssertEqual(c.takeLiveSection(.chorus, number: 2), .rejected(.noSuchSection))
    }
}
