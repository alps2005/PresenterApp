import XCTest
@testable import PresenterCore

@MainActor
final class CCLITests: XCTestCase {
    private func makeSong(info: SongInfo? = SongInfo(authors: ["John Newton"], copyright: "Public Domain", ccliNumber: "22025"))
        throws -> (PresentationCoordinator, PresentationItem, PresentationDocument) {
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let item = try XCTUnwrap(coordinator.addSong(title: "Amazing Grace", lyrics: "Verse 1\nA\n\nChorus\nB\n\nVerse 2\nC"))
        let song = try XCTUnwrap(coordinator.project.presentation(forItem: item.id))
        if let info { coordinator.setSongInfo(info, presentationID: song.id) }
        return (coordinator, item, try XCTUnwrap(coordinator.project.presentation(forItem: item.id)))
    }

    func testCreditLine() {
        let info = SongInfo(authors: ["Chris Tomlin", "John Newton"], copyright: "2006 sixsteps Music", ccliNumber: "4768151")
        XCTAssertEqual(info.creditLine(title: "Amazing Grace (My Chains Are Gone)", licenseNumber: "123"),
                       "“Amazing Grace (My Chains Are Gone)” · Chris Tomlin, John Newton · © 2006 sixsteps Music · CCLI Song # 4768151 · CCLI License # 123")
        XCTAssertEqual(SongInfo(copyright: "Public Domain").creditLine(title: "", licenseNumber: ""), "Public Domain")
    }

    func testCreditsShowOnTheFirstAndLastSlides() throws {
        let (c, item, song) = try makeSong()
        c.setCCLISettings(CCLISettings(licenseNumber: "CCLI 98-76"))
        XCTAssertEqual(c.project.ccli.licenseNumber, "9876", "Digits only")
        XCTAssertNil(c.audienceCredits, "Nothing live")

        c.takeLive(slideID: song.slides[0].id, inItem: item.id)
        XCTAssertEqual(c.audienceCredits, "“Amazing Grace” · John Newton · Public Domain · CCLI Song # 22025 · CCLI License # 9876")
        c.nextSlide()
        XCTAssertNil(c.audienceCredits, "Not in the middle")
        c.nextSlide()
        XCTAssertNotNil(c.audienceCredits, "The last slide")
        c.blackout()
        XCTAssertNil(c.audienceCredits, "Never over a blackout")
        c.restoreOutput()

        c.setCCLISettings(CCLISettings(licenseNumber: "9876", showsCredits: false))
        XCTAssertNil(c.audienceCredits, "Turned off")
        c.undo()
        XCTAssertTrue(c.project.ccli.showsCredits)
    }

    func testCreditsFollowTheArrangement() throws {
        let (c, item, song) = try makeSong()
        let order = try XCTUnwrap(c.addArrangement(name: "O", groups: ["Chorus", "Verse 1", "Chorus"], toPresentation: song.id))
        c.setActiveArrangement(order.id, inPresentation: song.id)
        let chorus = try XCTUnwrap(song.slides(inGroup: "Chorus").first)
        c.takeLive(slideID: chorus.id, inItem: item.id, occurrence: 0)
        XCTAssertNotNil(c.audienceCredits, "First in the song order")
        c.nextSlide()
        XCTAssertNil(c.audienceCredits)
        c.nextSlide()
        XCTAssertEqual(c.state.live?.position.occurrence, 1)
        XCTAssertNotNil(c.audienceCredits, "The chorus's last time is the last slide")
    }

    func testNoCreditsWithoutDetailsOrForOtherKinds() throws {
        let (c, item, song) = try makeSong(info: nil)
        c.takeLive(slideID: song.slides[0].id, inItem: item.id)
        XCTAssertNil(c.audienceCredits, "No credits filled in")

        c.setSongInfo(SongInfo(ccliNumber: "1"), presentationID: song.id)
        c.setKind(.presentation, presentationID: song.id)
        c.takeLive(slideID: song.slides[0].id, inItem: item.id)
        XCTAssertNil(c.audienceCredits, "Only songs")
    }

    func testSongWentLiveOncePerVisit() throws {
        let (c, item, song) = try makeSong()
        let deck = c.addPresentation(title: "Welcome")
        var reported: [String] = []
        c.onSongWentLive = { reported.append($0.title) }
        c.takeLive(slideID: song.slides[0].id, inItem: item.id)
        c.nextSlide()
        c.nextSlide()
        XCTAssertEqual(reported, ["Amazing Grace"], "Moving within the song isn't another use")
        c.nextSlide()
        XCTAssertEqual(c.state.live?.position.itemID, deck.id)
        XCTAssertEqual(reported, ["Amazing Grace"], "Presentations aren't reported")
    }

    func testImportedLicenseFillsAnEmptyOne() throws {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        var song = ImportedSong(title: "S", sections: [.init(label: "Verse", slides: [["a"]])])
        song.licenseNumber = "555"
        c.importSongs([song])
        XCTAssertEqual(c.project.ccli.licenseNumber, "555")
        song.licenseNumber = "777"
        c.importSongs([song])
        XCTAssertEqual(c.project.ccli.licenseNumber, "555", "Never replaces one already set")
    }

    func testFormat8FilesGetDefaultSettings() throws {
        let data = try JSONEncoder().encode(ProjectDocument(name: "T", ccli: CCLISettings(licenseNumber: "1", showsCredits: false)))
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: data).ccli, CCLISettings(licenseNumber: "1", showsCredits: false))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["ccli"] = nil
        let legacy = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.ccli, CCLISettings())
        let look = try JSONDecoder().decode(OutputLook.self, from: Data(#"{"showsProps":false}"#.utf8))
        XCTAssertTrue(look.showsCredits)
    }

    func testUsageLogRecordsOncePerDayAndReports() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = SongUsageLog(fileURL: folder.appendingPathComponent("SongUsage.jsonl"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let sunday = Date(timeIntervalSince1970: 1_790_000_000)
        var grace = PresentationDocument(title: "Amazing Grace", song: SongInfo(authors: ["John Newton"], ccliNumber: "22025"), kind: .song)
        let other = PresentationDocument(title: "No Number", kind: .song)

        try log.record(grace, at: sunday, calendar: calendar)
        try log.record(grace, at: sunday.addingTimeInterval(3600), calendar: calendar)
        try log.record(other, at: sunday, calendar: calendar)
        grace.title = "Amazing Grace (Renamed)"
        try log.record(grace, at: sunday.addingTimeInterval(7 * 86_400), calendar: calendar)
        XCTAssertEqual(try log.entries().count, 3, "Twice in one day is one use")

        let rows = SongUsageLog.report(try log.entries(), from: sunday, to: sunday.addingTimeInterval(7 * 86_400), calendar: calendar)
        XCTAssertEqual(rows.map(\.title), ["Amazing Grace (Renamed)", "No Number"])
        XCTAssertEqual(rows.map(\.uses), [2, 1])
        XCTAssertEqual(SongUsageLog.report(try log.entries(), from: sunday, to: sunday, calendar: calendar).map(\.uses), [1, 1],
                       "Whole days only")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let row = SongUsageLog.Row(title: "Hello, \"World\"", ccliNumber: "1", authors: "A", uses: 2, lastUsed: sunday)
        XCTAssertEqual(SongUsageLog.csv([row], dateFormatter: formatter),
                       "Title,Writers,CCLI Song Number,Times Used,Last Used\n\"Hello, \"\"World\"\"\",A,1,2,2026-09-21\n")
    }
}
