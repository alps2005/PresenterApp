import CoreGraphics
import XCTest
@testable import PresenterCore

final class OutputPlannerTests: XCTestCase {
    private let laptop = DisplayInfo(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), isPrimary: true)
    private let projector = DisplayInfo(id: 2, name: "Projector", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), isPrimary: false)
    private let monitor = DisplayInfo(id: 3, name: "Stage Monitor", frame: CGRect(x: 3432, y: 0, width: 1920, height: 1080), isPrimary: false)

    func testOutputsStartOff() {
        let planner = OutputPlanner(displays: [laptop, projector])
        for role in OutputRole.allCases {
            XCTAssertEqual(planner.status(role), .off)
            XCTAssertEqual(planner.placement(role), .hidden)
        }
    }

    func testCandidatesExcludeTheOperatorsDisplay() {
        var planner = OutputPlanner(displays: [laptop, projector, monitor])
        // Before the operator window reports its screen, the primary display is assumed.
        XCTAssertEqual(planner.fullScreenCandidates(.audience).map(\.id), [2, 3])
        planner.operatorDisplayID = 2
        XCTAssertEqual(planner.fullScreenCandidates(.audience).map(\.id), [1, 3])
    }

    func testCandidatesExcludeTheOtherOutputsDisplay() {
        var planner = OutputPlanner(displays: [laptop, projector, monitor], operatorDisplayID: 1)
        planner.show(.display(2), for: .audience)
        XCTAssertEqual(planner.fullScreenCandidates(.stage).map(\.id), [3])
        // A windowed or switched-off output doesn't hold a display.
        planner.hide(.audience)
        XCTAssertEqual(planner.fullScreenCandidates(.stage).map(\.id), [2, 3])
    }

    func testBothOutputsNeverShareAScreen() {
        var planner = OutputPlanner(displays: [laptop, projector, monitor], operatorDisplayID: 1)
        XCTAssertTrue(planner.show(.display(2), for: .audience))
        XCTAssertFalse(planner.show(.display(2), for: .stage))
        XCTAssertEqual(planner.status(.stage), .off)
        XCTAssertTrue(planner.show(.display(3), for: .stage))
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
        XCTAssertEqual(planner.placement(.stage), .fullScreen(displayID: 3))
    }

    func testMissingDisplayHidesTheOutputAndReconnectRestoresIt() {
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 1)
        planner.show(.display(2), for: .audience)
        XCTAssertEqual(planner.status(.audience), .fullScreen(displayName: "Projector"))

        planner.displays = [laptop]
        XCTAssertEqual(planner.status(.audience), .displayMissing(displayName: "Projector"))
        XCTAssertEqual(planner.placement(.audience), .hidden)
        XCTAssertTrue(planner.isEnabled(.audience), "The operator's choice is kept while the display is gone")

        planner.displays = [laptop, projector]
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
    }

    func testToggleRemembersTheTarget() {
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 1)
        planner.toggle(.audience)
        XCTAssertEqual(planner.placement(.audience), .windowed)
        planner.show(.display(2), for: .audience)
        planner.toggle(.audience)
        XCTAssertEqual(planner.status(.audience), .off)
        planner.toggle(.audience)
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
    }

    func testClosingTheWindowTurnsTheOutputOff() {
        var planner = OutputPlanner(displays: [laptop])
        planner.show(.windowed, for: .stage)
        planner.hide(.stage)
        XCTAssertFalse(planner.isEnabled(.stage))
        XCTAssertEqual(planner.target(.stage), .windowed)
    }
}
