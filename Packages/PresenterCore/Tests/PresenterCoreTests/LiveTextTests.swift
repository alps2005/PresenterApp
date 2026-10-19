import Foundation
import XCTest
@testable import PresenterCore

/// Live values in slide text (`{timer:Name}`, `{clock}`), and the token scanner messages share.
@MainActor
final class LiveTextTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    func testTokensAreFoundTrimmedAndEmptyBracesSkipped() {
        XCTAssertEqual(TextTokens.tokens(in: "A {one} b { two } {} {timer:Sermon} {open"), ["one", "two", "timer:Sermon"])
        XCTAssertEqual(TextTokens.timerName("Timer: Sermon "), "Sermon")
        XCTAssertNil(TextTokens.timerName("clock"))
    }

    func testReplacingLeavesUnknownTokensAndOtherTextAlone() {
        let text = "{a} and {b} {} {c"
        XCTAssertEqual(TextTokens.replacing(in: text) { $0 == "a" ? "1" : nil }, "1 and {b} {} {c")
    }

    func testOnlyTimersAndTheClockAreLive() {
        XCTAssertTrue(LiveText.hasTokens("Sermon ends in {timer:Sermon}"))
        XCTAssertTrue(LiveText.hasTokens("It's {CLOCK}"))
        XCTAssertTrue(LiveText.hasTokens("{clock:seconds}"))
        XCTAssertFalse(LiveText.hasTokens("Shout to the Lord {Chorus}"))
        XCTAssertFalse(LiveText.hasTokens("No braces"))
        XCTAssertEqual(LiveText.timerNames(in: "{timer:Sermon} {clock} {timer: Walk-in }"), ["Sermon", "Walk-in"])
    }

    func testResolvingFillsInTimersAndTheClockAndKeepsLyricBraces() {
        let date = Date(timeIntervalSince1970: 9 * 3600 + 41 * 60 + 7)
        let text = "{Chorus} {timer:Sermon} at {clock} ({clock:seconds}) {timer:Gone}."
        let resolved = LiveText.resolve(text, at: date, timerText: { $0 == "Sermon" ? "4:05" : nil }, calendar: utc,
                                        locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(resolved, "{Chorus} 4:05 at 09:41 (09:41:07) .")
        // A 12-hour locale gets its own style.
        let american = LiveText.clockText(date, seconds: false, calendar: utc, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(american.hasPrefix("9:41") && american.contains("AM"), american)
        XCTAssertEqual(LiveText.resolve("Plain", at: date, timerText: { _ in "x" }), "Plain")
    }

    func testTheCoordinatorUsesTheRunningTimerByNameIgnoringCase() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        c.now = { now }
        let sermon = try XCTUnwrap(c.project.timers.first { $0.name == "Sermon" })
        c.startTimer(sermon.id)
        now += 65
        XCTAssertEqual(c.timerText(named: "sermon", at: now), "28:55")
        XCTAssertNil(c.timerText(named: "Nope", at: now))
        XCTAssertEqual(c.liveText("Left: {timer:SERMON}", at: now), "Left: 28:55")
    }

    func testMessagesStillFillBlanksAndTimers() {
        let message = MessageDefinition(name: "M", text: "Car { Plate } – {timer:Sermon} – {Plate}")
        XCTAssertEqual(message.fields, ["Plate"])
        XCTAssertEqual(message.rendered(values: ["Plate": "ABC"]) { _ in "1:00" }, "Car ABC – 1:00 – ABC")
    }
}
