import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class TimerTests: XCTestCase {
    func testCountdownPausesResumesAndOverruns() {
        var clock = Date(timeIntervalSince1970: 0)
        let timer = TimerDefinition(name: "Sermon", kind: .countdown(seconds: 60))
        let c = PresentationCoordinator(project: ProjectDocument(name: "T", timers: [timer]))
        c.now = { clock }

        c.startTimer(timer.id); clock += 20
        XCTAssertEqual(c.timerSeconds(timer.id, at: clock), 40)
        c.stopTimer(timer.id); clock += 100
        XCTAssertEqual(c.timerSeconds(timer.id, at: clock), 40)
        c.startTimer(timer.id); clock += 50
        XCTAssertEqual(c.timerSeconds(timer.id, at: clock), -10)
        XCTAssertEqual(TimerDefinition.format(-10), "-0:10")
        c.resetTimer(timer.id)
        XCTAssertEqual(c.timerSeconds(timer.id, at: clock), 60)
        XCTAssertEqual(c.startTimer(UUID()), .rejected(.unknownTimer))
    }

    func testCountdownToTimeRollsPastMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let timer = TimerDefinition(name: "Late", kind: .countdownTo(hour: 0, minute: 30))
        let at2350 = Date(timeIntervalSince1970: 23 * 3600 + 50 * 60)
        XCTAssertEqual(timer.seconds(run: TimerRun(), now: at2350, calendar: calendar), 40 * 60)

        let service = TimerDefinition(name: "Service", kind: .countdownTo(hour: 10, minute: 0))
        let at1005 = Date(timeIntervalSince1970: 10 * 3600 + 5 * 60)
        XCTAssertEqual(service.seconds(run: TimerRun(), now: at1005, calendar: calendar), -5 * 60)
    }

    func testFormatting() {
        XCTAssertEqual(TimerDefinition.format(245), "4:05")
        XCTAssertEqual(TimerDefinition.format(3723), "1:02:03")
    }

    func testStageMessageAndDeletingTheStageTimer() {
        let timer = TimerDefinition(name: "T", kind: .elapsed)
        let c = PresentationCoordinator(project: ProjectDocument(name: "T", timers: [timer], stage: StageSettings(timerID: timer.id)))
        c.showStageMessage("  Wrap up  ")
        XCTAssertEqual(c.state.stageMessage, "Wrap up")
        c.showStageMessage("")
        XCTAssertNil(c.state.stageMessage)

        c.deleteTimer(timer.id)
        XCTAssertNil(c.project.stage.timerID)
        c.undo()
        XCTAssertEqual(c.project.stage.timerID, timer.id)
    }

    func testOldProjectsGetDefaultTimers() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProjectDocument(name: "P"))) as! [String: Any]
        json.removeValue(forKey: "timers"); json.removeValue(forKey: "stage")
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.timers.map(\.name), ["Service Starts", "Sermon"])
    }
}
