import Foundation
import XCTest
@testable import PresenterCore

/// The message, timer, stage and prop library commands, and live video mute.
@MainActor
final class ShowControlsTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000)

    private func makeCoordinator(_ project: ProjectDocument = ProjectDocument(name: "T")) -> PresentationCoordinator {
        let c = PresentationCoordinator(project: project)
        c.now = { [unowned self] in clock }
        return c
    }

    // MARK: Messages

    func testAddingAMessageKeepsItsSettingsInOneUndoStep() {
        let c = makeCoordinator()
        let before = c.project.messages
        let draft = MessageDefinition(name: "", text: "Car {Plate}", position: .top, fontSize: 80, textColor: .black)

        let added = c.addMessage(draft)

        XCTAssertEqual(added.name, "Message")
        XCTAssertEqual(c.project.messages.last, added)
        XCTAssertEqual(added.position, .top)
        XCTAssertEqual(added.fontSize, 80)
        XCTAssertEqual(added.textColor, .black)
        c.undo()
        XCTAssertEqual(c.project.messages, before)
        XCTAssertFalse(c.canUndo)
    }

    func testUpdateAndDeleteMessage() {
        let c = makeCoordinator()
        var message = c.addMessage(name: "Nursery", text: "Child {Number}")
        message.text = "Parent of {Number}"

        XCTAssertEqual(c.updateMessage(message), .applied)
        XCTAssertEqual(c.project.message(withID: message.id)?.text, "Parent of {Number}")
        XCTAssertEqual(c.deleteMessage(message.id), .applied)
        XCTAssertNil(c.project.message(withID: message.id))
        XCTAssertEqual(c.updateMessage(message), .rejected(.unknownMessage))
        XCTAssertEqual(c.deleteMessage(message.id), .rejected(.unknownMessage))
        c.undo()
        XCTAssertNotNil(c.project.message(withID: message.id))
    }

    // MARK: Timers and stage

    func testAddAndUpdateTimer() {
        let c = makeCoordinator()
        var timer = c.addTimer(name: "", kind: .countdown(seconds: 60))
        XCTAssertEqual(timer.name, "Timer")

        c.startTimer(timer.id)
        clock += 10
        XCTAssertTrue(c.timerRun(for: timer.id).isRunning)

        // Renaming keeps it running; changing its kind resets it.
        timer.name = "Walk-in"
        c.updateTimer(timer)
        XCTAssertTrue(c.timerRun(for: timer.id).isRunning)
        timer.kind = .countdown(seconds: 120)
        c.updateTimer(timer)
        XCTAssertEqual(c.timerRun(for: timer.id), TimerRun())
        XCTAssertEqual(c.timerSeconds(timer.id, at: clock), 120)

        XCTAssertEqual(c.updateTimer(TimerDefinition(name: "Gone", kind: .elapsed)), .rejected(.unknownTimer))
    }

    func testStageSettingsRejectAnUnknownTimer() {
        let c = makeCoordinator()
        let timer = c.project.timers[0]

        XCTAssertEqual(c.setStageSettings(StageSettings(timerID: timer.id, showsClock: false)), .applied)
        XCTAssertEqual(c.project.stage.timerID, timer.id)
        XCTAssertFalse(c.project.stage.showsClock)

        XCTAssertEqual(c.setStageSettings(StageSettings(timerID: UUID())), .rejected(.unknownTimer))
        XCTAssertEqual(c.project.stage.timerID, timer.id)
    }

    func testHideStageMessage() {
        let c = makeCoordinator()
        c.showStageMessage("Two minutes")
        XCTAssertEqual(c.hideStageMessage(), .applied)
        XCTAssertNil(c.state.stageMessage)
    }

    // MARK: Props

    func testRenameProp() {
        let c = makeCoordinator()
        let prop = c.addProp(name: "Logo")

        c.renameProp(prop.id, to: "Church Logo")
        XCTAssertEqual(c.project.prop(withID: prop.id)?.label, "Church Logo")
        // A blank name falls back to the prop's default name.
        c.renameProp(prop.id, to: "   ")
        XCTAssertNil(c.project.prop(withID: prop.id)?.label)
        XCTAssertEqual(c.renameProp(UUID(), to: "X"), .rejected(.unknownProp))
    }

    // MARK: Edit dates

    func testEditsAreDatedByTheCoordinatorsClock() {
        let presentation = PresentationDocument(title: "P", slides: [.text("One")])
        let c = makeCoordinator(ProjectDocument(name: "T", presentations: [presentation]))
        clock = Date(timeIntervalSince1970: 5_000)

        c.renamePresentation(presentation.id, to: "Renamed")
        XCTAssertEqual(c.project.presentation(withID: presentation.id)?.updatedAt, clock)

        clock += 60
        c.updateSlideText("Welcome", slideID: c.project.props.slides[0].id, inPresentation: c.project.props.id)
        XCTAssertEqual(c.project.props.updatedAt, clock)
    }

    // MARK: Live video

    private func videoFixture() -> (PresentationCoordinator, PresentationItem, [SlideDocument], MediaAsset) {
        let asset = MediaAsset(kind: .video, originalFilename: "loop.mp4", storedFilename: "l.mp4",
                               pixelWidth: 1920, pixelHeight: 1080, duration: 10)
        let video = SlideBackground.video(VideoBackground(assetID: asset.id))
        let slides = [
            SlideDocument(elements: [.text(TextElement(text: "One"))], background: video),
            SlideDocument(elements: [.text(TextElement(text: "Two"))], background: .transparent),
            SlideDocument(elements: [.text(TextElement(text: "Three"))], background: video),
            SlideDocument(elements: [.text(TextElement(text: "Four"))], background: .color(RGBAColor(red: 1, green: 0, blue: 0))),
        ]
        let presentation = PresentationDocument(title: "P", slides: slides)
        let item = PresentationItem(presentationID: presentation.id)
        let c = makeCoordinator(ProjectDocument(name: "T", presentations: [presentation],
                                                playlist: PlaylistDocument(title: "P", items: [item]), mediaAssets: [asset]))
        return (c, item, slides, asset)
    }

    private func liveVideo(_ c: PresentationCoordinator) -> VideoBackground? {
        if case .video(let video) = c.state.liveBackground { return video }
        return nil
    }

    func testMutingTheLiveVideoLastsWhileItKeepsPlaying() {
        let (c, item, slides, _) = videoFixture()
        XCTAssertEqual(c.setLiveVideoMuted(false), .rejected(.nothingLive))

        c.takeLive(slideID: slides[0].id, inItem: item.id)
        XCTAssertEqual(liveVideo(c)?.isMuted, true)
        XCTAssertEqual(c.setLiveVideoMuted(false), .applied)
        XCTAssertEqual(liveVideo(c)?.isMuted, false)

        // A transparent slide over it, then another slide with the same video: still unmuted.
        c.nextSlide()
        XCTAssertEqual(liveVideo(c)?.isMuted, false)
        c.nextSlide()
        XCTAssertEqual(liveVideo(c)?.isMuted, false)
        XCTAssertFalse(c.canUndo, "Mute is live state, not an edit")
        // The slide itself is unchanged.
        XCTAssertEqual(c.project.presentations[0].slides[2].background, slides[2].background)

        // Once the video is replaced, the next time it comes back it starts with the slide's own setting.
        c.nextSlide()
        c.takeLive(slideID: slides[0].id, inItem: item.id)
        XCTAssertEqual(liveVideo(c)?.isMuted, true)
    }

    func testOutputPreviewLeavesOpaqueSlidesAlone() {
        let (c, item, slides, _) = videoFixture()
        c.takeLive(slideID: slides[0].id, inItem: item.id)
        let red = RenderedSlide(slide: slides[3], background: slides[3].background)
        XCTAssertEqual(c.outputPreview(of: red), red)
    }
}
