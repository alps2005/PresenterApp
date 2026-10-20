import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class ActionTests: XCTestCase {
    /// A song whose second slide has actions, in a project with the default timers, message and props.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let song: PresentationDocument
        let item: PresentationItem
        let sermon: TimerDefinition
        let nursery: MessageDefinition
        let logoID: UUID
        let lyrics: StageLayout
    }

    private func makeFixture(actions: [ShowAction] = []) -> Fixture {
        var project = ProjectDocument(name: "T", presentations: [], playlist: PlaylistDocument(title: "S"))
        var second = SlideDocument.text("b")
        second.actions = actions
        let song = PresentationDocument(title: "Song", slides: [.text("a"), second, .text("c")])
        let item = PresentationItem(presentationID: song.id)
        project.presentations = [song]
        project.playlist.items = [item]
        let coordinator = PresentationCoordinator(project: project)
        var clock = Date(timeIntervalSince1970: 1_000)
        coordinator.now = {
            clock += 1
            return clock
        }
        return Fixture(coordinator: coordinator, song: song, item: item,
                       sermon: project.timers.first { $0.name == "Sermon" }!, nursery: project.messages[0],
                       logoID: project.props.slides[0].id, lyrics: project.stageLayouts[0])
    }

    func testSlideActionsRunWhenTheSlideGoesLiveOnce() throws {
        let f = makeFixture()
        let c = f.coordinator
        let actions: [ShowAction] = [
            .startTimer(timerID: f.sermon.id),
            .showMessage(messageID: f.nursery.id, values: ["Number": "42"]),
            .showProp(propID: f.logoID),
            .showStageMessage(text: "Next: offering"),
            .setStageLayout(layoutID: f.lyrics.id),
        ]
        c.setSlideActions(actions, slideID: f.song.slides[1].id, inPresentation: f.song.id)

        c.takeLive(slideID: f.song.slides[0].id, inItem: f.item.id)
        XCTAssertFalse(c.timerRun(for: f.sermon.id).isRunning, "Not before its slide")

        c.nextSlide()
        XCTAssertTrue(c.timerRun(for: f.sermon.id).isRunning)
        XCTAssertEqual(c.state.activeMessage, ActiveMessage(messageID: f.nursery.id, values: ["Number": "42"]))
        XCTAssertEqual(c.state.activeProps, [f.logoID])
        XCTAssertEqual(c.state.stageMessage, "Next: offering")
        XCTAssertEqual(c.stageLayout, f.lyrics)
        XCTAssertNil(c.project.stage.layoutID, "The project's own choice stays as it was")
        XCTAssertNil(c.lastRejection)

        // Taken live again: the prop isn't toggled off and nothing reruns.
        c.clearMessages()
        c.takeLive(slideID: f.song.slides[1].id, inItem: f.item.id)
        XCTAssertNil(c.state.activeMessage)
        XCTAssertEqual(c.state.activeProps, [f.logoID])
    }

    func testTheOperatorsLayoutChoiceReplacesAnActions() throws {
        let f = makeFixture()
        let c = f.coordinator
        let speaker = c.project.stageLayouts[1]
        c.setSlideActions([.setStageLayout(layoutID: f.lyrics.id)], slideID: f.song.slides[0].id, inPresentation: f.song.id)
        c.setStageLayout(speaker.id)
        c.takeLive(slideID: f.song.slides[0].id, inItem: f.item.id)
        XCTAssertEqual(c.stageLayoutID, f.lyrics.id)

        c.setStageLayout(nil)
        XCTAssertNil(c.stageLayout, "The operator's pick wins")
        XCTAssertNil(c.state.stageLayoutOverride)

        // A layout an action chose goes when the layout is deleted.
        c.takeLive(slideID: f.song.slides[1].id, inItem: f.item.id)
        c.takeLive(slideID: f.song.slides[0].id, inItem: f.item.id)
        XCTAssertEqual(c.stageLayoutID, f.lyrics.id)
        c.deleteStageLayout(f.lyrics.id)
        XCTAssertNil(c.state.stageLayoutOverride)
        XCTAssertNil(c.stageLayout)
    }

    func testMacrosRunNestedButNotForever() throws {
        let f = makeFixture()
        let c = f.coordinator
        let inner = c.addMacro(named: "Inner")
        var outer = c.addMacro(named: "Outer")
        c.updateMacro(Macro(id: inner.id, name: "Inner", actions: [.showProp(propID: f.logoID), .runMacro(macroID: outer.id)]))
        outer.actions = [.restartTimer(timerID: f.sermon.id), .runMacro(macroID: inner.id)]
        c.updateMacro(outer)

        XCTAssertEqual(c.runMacro(outer.id), .applied, "Two macros that run each other stop")
        XCTAssertTrue(c.timerRun(for: f.sermon.id).isRunning)
        XCTAssertEqual(c.state.activeProps, [f.logoID], "Shown once, not toggled back off")
        XCTAssertEqual(c.runMacro(UUID()), .rejected(.unknownMacro))
    }

    func testMacrosClearAndBlackOut() {
        let f = makeFixture()
        let c = f.coordinator
        c.takeLive(slideID: f.song.slides[0].id, inItem: f.item.id)
        c.toggleProp(f.logoID)
        let macro = c.addMacro(named: "End")
        c.updateMacro(Macro(id: macro.id, name: "End", actions: [.clearProps, .clearSlide, .clearMessages, .blackout]))
        c.runMacro(macro.id)
        XCTAssertNil(c.state.live)
        XCTAssertTrue(c.state.activeProps.isEmpty)
        XCTAssertTrue(c.state.isBlackout)
        XCTAssertNil(c.lastRejection, "Clear Messages with no message is passed over quietly")
    }

    func testSlidesDontKeepActionsThatUndoTheTake() {
        let f = makeFixture()
        let c = f.coordinator
        c.setSlideActions([.clearSlide, .blackout, .clearAll, .clearProps], slideID: f.song.slides[1].id, inPresentation: f.song.id)
        XCTAssertEqual(c.project.presentation(withID: f.song.id)?.slides[1].actions, [.clearProps])
    }

    func testEditingMacrosUndoes() throws {
        let f = makeFixture()
        let c = f.coordinator
        let macro = c.addMacro(named: "")
        XCTAssertEqual(macro.name, "Untitled Macro")
        let copy = try XCTUnwrap(c.duplicateMacro(macro.id))
        XCTAssertEqual(c.project.macros.map(\.id), [macro.id, copy.id])
        XCTAssertEqual(c.deleteMacro(macro.id), .applied)
        XCTAssertEqual(c.project.macros.map(\.id), [copy.id])
        c.undo()
        XCTAssertEqual(c.project.macros.map(\.id), [macro.id, copy.id])
        XCTAssertEqual(c.deleteMacro(UUID()), .rejected(.unknownMacro))
    }

    func testDeletingAudioRemovesItFromMacros() throws {
        let f = makeFixture()
        let c = f.coordinator
        let asset = MediaAsset(kind: .audio, originalFilename: "walk-in.m4a", storedFilename: "x.m4a", pixelWidth: 0, pixelHeight: 0)
        c.addMediaAsset(asset)
        let macro = c.addMacro(named: "Walk-in")
        c.updateMacro(Macro(id: macro.id, name: "Walk-in", actions: [.playAudio(track: AudioTrack(assetID: asset.id)), .stopAudio]))
        XCTAssertEqual(c.project.macrosUsing(asset: asset.id).map(\.id), [macro.id])

        c.runMacro(macro.id)
        XCTAssertNil(c.state.audio, "Played, then stopped")
        c.removeMediaAsset(asset.id)
        XCTAssertEqual(c.project.macro(withID: macro.id)?.actions, [.stopAudio])
    }

    func testActionsAndMacrosRoundTripAndOlderFilesHaveNone() throws {
        var slide = SlideDocument.text("a")
        slide.actions = [.restartTimer(timerID: UUID()), .setStageLayout(layoutID: nil), .showStageMessage(text: "Hi")]
        let data = try JSONEncoder().encode(slide)
        XCTAssertEqual(try JSONDecoder().decode(SlideDocument.self, from: data), slide)

        let plain = try JSONEncoder().encode(SlideDocument.text("b"))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("actions"), "Slides without actions save as before")
        XCTAssertEqual(try JSONDecoder().decode(SlideDocument.self, from: plain).actions, [])

        var project = ProjectDocument(name: "T")
        project.macros = [Macro(name: "M", color: .white, actions: [.clearAll])]
        let projectData = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: projectData).macros, project.macros)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: projectData) as? [String: Any])
        old["macros"] = nil
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: old)).macros, [])
    }
}
