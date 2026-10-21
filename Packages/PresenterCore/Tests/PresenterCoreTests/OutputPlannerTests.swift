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

    func testDisplaysInUseByTheOtherOutput() {
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 1)
        XCTAssertEqual(planner.displaysInUse(byOtherThan: .stage), [])
        planner.show(.display(2), for: .audience)
        // The stage display has nowhere to go full screen, and the menu can say why.
        XCTAssertEqual(planner.fullScreenCandidates(.stage), [])
        XCTAssertEqual(planner.displaysInUse(byOtherThan: .stage).map(\.id), [2])
        XCTAssertEqual(planner.displaysInUse(byOtherThan: .audience), [])
        planner.show(.windowed, for: .audience)
        XCTAssertEqual(planner.displaysInUse(byOtherThan: .stage), [])
        planner.show(.display(2), for: .audience)
        planner.hide(.audience)
        XCTAssertEqual(planner.displaysInUse(byOtherThan: .stage), [])
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

    // MARK: Remembered displays

    private func display(_ id: UInt32, _ name: String, vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0,
                         x: CGFloat = 1512) -> DisplayInfo {
        DisplayInfo(id: id, name: name, frame: CGRect(x: x, y: 0, width: 1920, height: 1080), isPrimary: false,
                    identity: DisplayIdentity(vendor: vendor, model: model, serial: serial, name: name))
    }

    func testIdentityMatchesBySerialThenModelThenName() {
        let epson = DisplayIdentity(vendor: 7, model: 9, serial: 42, name: "EPSON PJ")
        // Same serial wins even under another ID and name.
        XCTAssertEqual(epson.match(in: [display(5, "Projector", vendor: 7, model: 9, serial: 42)])?.id, 5)
        // Another unit of the same model, when it's the only one.
        XCTAssertEqual(epson.match(in: [display(6, "EPSON PJ", vendor: 7, model: 9, serial: 43)])?.id, 6)
        // Two of the same model can't be told apart.
        XCTAssertNil(epson.match(in: [display(6, "EPSON PJ", vendor: 7, model: 9, serial: 43),
                                      display(8, "EPSON PJ", vendor: 7, model: 9, serial: 44, x: 3432)]))
        // A display that reports nothing is found by its name, if no other has it.
        XCTAssertEqual(DisplayIdentity(name: "TV").match(in: [laptop, display(4, "TV")])?.id, 4)
        XCTAssertNil(DisplayIdentity(name: "TV").match(in: [display(4, "TV"), display(9, "TV", x: 3432)]))
    }

    func testSavedOutputsComeBackOnTheSameDisplayUnderANewID() {
        let projectorIdentity = DisplayIdentity(vendor: 7, model: 9, serial: 42, name: "Projector")
        var before = OutputPlanner(displays: [laptop, display(2, "Projector", vendor: 7, model: 9, serial: 42)], operatorDisplayID: 1)
        before.show(.display(2), for: .audience)
        before.show(.windowed, for: .stage)
        XCTAssertEqual(before.saved(.audience), SavedOutput(isEnabled: true, display: projectorIdentity))
        XCTAssertEqual(before.saved(.stage), SavedOutput(isEnabled: true))

        var after = OutputPlanner(displays: [laptop, display(77, "Projector", vendor: 7, model: 9, serial: 42)], operatorDisplayID: 1)
        after.restore(before.saved(.audience), for: .audience)
        after.restore(before.saved(.stage), for: .stage)
        XCTAssertEqual(after.placement(.audience), .fullScreen(displayID: 77))
        XCTAssertEqual(after.status(.audience), .fullScreen(displayName: "Projector"))
        XCTAssertEqual(after.placement(.stage), .windowed)
    }

    func testARememberedDisplayThatIsntConnectedWaitsForIt() {
        let saved = SavedOutput(isEnabled: true, display: DisplayIdentity(vendor: 7, model: 9, serial: 42, name: "Projector"))
        var planner = OutputPlanner(displays: [laptop], operatorDisplayID: 1)
        planner.restore(saved, for: .audience)
        XCTAssertEqual(planner.status(.audience), .displayMissing(displayName: "Projector"))
        XCTAssertEqual(planner.placement(.audience), .hidden)
        // Remembered as it was, so a launch without the projector doesn't forget it.
        XCTAssertEqual(planner.saved(.audience), saved)

        planner.displays = [laptop, display(12, "Projector", vendor: 7, model: 9, serial: 42)]
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 12))
    }

    func testAnOutputThatWasOffStaysOffButKeepsItsDisplay() {
        let saved = SavedOutput(isEnabled: false, display: DisplayIdentity(name: "Projector"))
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 1)
        planner.restore(saved, for: .audience)
        XCTAssertEqual(planner.status(.audience), .off)
        XCTAssertTrue(planner.toggle(.audience))
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
    }

    func testRestoringNeverFillsTheOperatorsScreenOrTheOtherOutputs() {
        let projectorSaved = SavedOutput(isEnabled: true, display: DisplayIdentity(name: "Projector"))
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 2)
        planner.restore(projectorSaved, for: .audience)
        XCTAssertEqual(planner.placement(.audience), .hidden)

        planner.operatorDisplayID = 1
        planner.restore(projectorSaved, for: .audience)
        planner.restore(projectorSaved, for: .stage)
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
        XCTAssertEqual(planner.placement(.stage), .hidden)
    }

    func testARememberedDisplayWithTheOperatorWindowWaitsForTheWindowToMove() {
        let saved = SavedOutput(isEnabled: true, display: DisplayIdentity(name: "Projector"))
        var planner = OutputPlanner(displays: [laptop, projector], operatorDisplayID: 2)
        planner.restore(saved, for: .audience)
        XCTAssertEqual(planner.status(.audience), .displayHasOperatorWindow(displayName: "Projector"))
        XCTAssertEqual(planner.placement(.audience), .hidden)
        XCTAssertEqual(planner.saved(.audience), saved)

        planner.operatorDisplayID = 1
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
        XCTAssertEqual(planner.status(.audience), .fullScreen(displayName: "Projector"))

        // Once it fills the projector, the operator window passing over it doesn't take it off.
        planner.operatorDisplayID = 2
        XCTAssertEqual(planner.placement(.audience), .fullScreen(displayID: 2))
    }

    func testAnIDTakenByAnotherDisplayIsntFilled() {
        var planner = OutputPlanner(displays: [laptop, display(2, "Projector", serial: 42)], operatorDisplayID: 1)
        planner.show(.display(2), for: .audience)
        // The projector leaves and a TV arrives with its old ID.
        planner.displays = [laptop, display(2, "TV")]
        XCTAssertEqual(planner.placement(.audience), .hidden)
        XCTAssertEqual(planner.status(.audience), .displayMissing(displayName: "Projector"))
    }
}
