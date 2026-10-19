import Foundation
import XCTest
@testable import PresenterCore

/// Stage layouts: presets, the library commands, choosing one, and file format 6.
@MainActor
final class StageLayoutTests: XCTestCase {
    private func makeCoordinator() -> PresentationCoordinator {
        PresentationCoordinator(project: ProjectDocument(name: "T"))
    }

    func testPresetsAndTheStandardLayoutFitOnScreen() {
        let layouts = StageLayout.presets() + [StageLayout.standard()]
        XCTAssertEqual(StageLayout.presets().map(\.name), ["Lyrics", "Speaker", "Slides"])
        for layout in layouts {
            XCTAssertFalse(layout.regions.isEmpty, layout.name)
            for region in layout.regions {
                XCTAssertEqual(region.frame, region.frame.clampedToCanvas(), "\(layout.name) \(region.kind.title)")
                XCTAssertTrue(StageRegion.fontSizeRange.contains(region.fontSize), "\(layout.name) \(region.kind.title)")
            }
            // The message sits on top of whatever it covers.
            XCTAssertEqual(layout.regions.last?.kind, .message, layout.name)
        }
    }

    func testANewProjectStartsWithThePresetsAndTheStandardLook() {
        let c = makeCoordinator()
        XCTAssertEqual(c.project.stageLayouts.map(\.name), ["Lyrics", "Speaker", "Slides"])
        XCTAssertNil(c.project.stage.layoutID)
        XCTAssertNil(c.stageLayout)
    }

    func testAddingALayoutStartsFromTheStandardOneOrCopiesAnother() throws {
        let c = makeCoordinator()
        let blank = try XCTUnwrap(c.addStageLayout(named: "  "))
        XCTAssertEqual(blank.name, "Stage Layout")
        XCTAssertEqual(blank.regions.map(\.kind), StageLayout.standard().regions.map(\.kind))

        let lyrics = c.project.stageLayouts[0]
        let copy = try XCTUnwrap(c.addStageLayout(named: "Band", basedOn: lyrics.id))
        XCTAssertEqual(copy.name, "Band")
        XCTAssertEqual(copy.regions.map(\.kind), lyrics.regions.map(\.kind))
        XCTAssertEqual(copy.regions.map(\.frame), lyrics.regions.map(\.frame))
        XCTAssertTrue(Set(copy.regions.map(\.id)).isDisjoint(with: lyrics.regions.map(\.id)))
        XCTAssertEqual(c.project.stageLayouts.last, copy)

        XCTAssertNil(c.addStageLayout(named: "Gone", basedOn: UUID()))
        XCTAssertEqual(c.lastRejection, .unknownStageLayout)

        c.undo()
        XCTAssertFalse(c.project.stageLayouts.contains { $0.id == copy.id })
    }

    func testEditsKeepRegionsOnScreenAndCoalesce() throws {
        let c = makeCoordinator()
        var layout = c.project.stageLayouts[0]
        let original = layout
        layout.regions[0].frame = NormalizedRect(x: 0.9, y: -0.2, width: 0.5, height: 0.3)
        layout.regions[0].fontSize = 9_000
        XCTAssertEqual(c.updateStageLayout(layout), .applied)
        layout.name = "Big Words"
        XCTAssertEqual(c.updateStageLayout(layout), .applied)

        let saved = try XCTUnwrap(c.project.stageLayout(withID: layout.id))
        XCTAssertEqual(saved.name, "Big Words")
        XCTAssertEqual(saved.regions[0].frame, NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 0.3))
        XCTAssertEqual(saved.regions[0].fontSize, StageRegion.fontSizeRange.upperBound)

        c.undo()
        XCTAssertEqual(c.project.stageLayout(withID: layout.id), original)
        XCTAssertEqual(c.updateStageLayout(StageLayout(name: "Nope")), .rejected(.unknownStageLayout))
    }

    func testChoosingAndDeletingTheLayoutInUse() {
        let c = makeCoordinator()
        let speaker = c.project.stageLayouts[1]
        XCTAssertEqual(c.setStageLayout(speaker.id), .applied)
        XCTAssertEqual(c.stageLayout, speaker)
        XCTAssertEqual(c.setStageLayout(UUID()), .rejected(.unknownStageLayout))
        XCTAssertEqual(c.project.stage.layoutID, speaker.id)

        XCTAssertEqual(c.deleteStageLayout(speaker.id), .applied)
        XCTAssertNil(c.project.stage.layoutID)
        XCTAssertNil(c.stageLayout)
        c.undo()
        XCTAssertEqual(c.stageLayout, speaker)

        XCTAssertEqual(c.setStageLayout(nil), .applied)
        XCTAssertNil(c.stageLayout)
    }

    func testDeletingATimerPointsItsRegionsAtTheStageTimer() throws {
        let c = makeCoordinator()
        let sermon = try XCTUnwrap(c.project.timers.last)
        var layout = c.project.stageLayouts[1]
        let index = try XCTUnwrap(layout.regions.firstIndex { if case .timer = $0.kind { true } else { false } })
        layout.regions[index].kind = .timer(sermon.id)
        c.updateStageLayout(layout)
        XCTAssertEqual(c.project.stageLayouts[1].regions[index].timerID(stageTimerID: nil), sermon.id)

        c.deleteTimer(sermon.id)
        XCTAssertEqual(c.project.stageLayouts[1].regions[index].kind, .timer(nil))
        let other = UUID()
        XCTAssertEqual(c.project.stageLayouts[1].regions[index].timerID(stageTimerID: other), other)
        c.undo()
        XCTAssertEqual(c.project.stageLayouts[1].regions[index].kind, .timer(sermon.id))
    }

    func testLayoutsRoundTripAndOlderFilesGetThePresets() throws {
        let c = makeCoordinator()
        let custom = try XCTUnwrap(c.addStageLayout(named: "Band", basedOn: c.project.stageLayouts[0].id))
        var edited = custom
        edited.regions.append(StageRegion(kind: .text("Watch the drummer"), frame: .centered(width: 0.5, height: 0.1)))
        c.updateStageLayout(edited)
        c.setStageLayout(custom.id)

        let data = try JSONEncoder().encode(c.project)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)
        XCTAssertEqual(decoded, c.project)
        XCTAssertEqual(decoded.stage.layoutID, custom.id)

        // A format 5 file has no layouts and no layout choice.
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["schemaVersion"] = 5
        old["stageLayouts"] = nil
        var stage = try XCTUnwrap(old["stage"] as? [String: Any])
        stage["layoutID"] = nil
        old["stage"] = stage
        let legacy = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.stageLayouts.map(\.name), ["Lyrics", "Speaker", "Slides"])
        XCTAssertNil(legacy.stage.layoutID)
        XCTAssertEqual(legacy.stage.showsClock, c.project.stage.showsClock)
    }
}
