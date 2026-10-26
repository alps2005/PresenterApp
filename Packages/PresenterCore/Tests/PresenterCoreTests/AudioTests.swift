import AVFoundation
import Foundation
import XCTest
@testable import PresenterCore

final class AudioPlanTests: XCTestCase {
    private let track = AudioTrack(assetID: UUID(), loops: true, fadeIn: 3)

    func testNothingPlayingAndNothingToPlayIsIdle() {
        XCTAssertEqual(AudioPlan.decide(playingStartID: nil, live: nil, stopFade: 2) { _ in true }, .idle)
    }

    func testANewStartStartsOrCrossfades() {
        let live = LiveAudio(track: track)
        XCTAssertEqual(AudioPlan.decide(playingStartID: nil, live: live, stopFade: 0) { _ in true }, .start(live))
        XCTAssertEqual(AudioPlan.decide(playingStartID: UUID(), live: live, stopFade: 0) { _ in true },
                       .crossfade(live, fadeOut: 3))
        var quick = live
        quick.track.fadeIn = 0
        XCTAssertEqual(AudioPlan.decide(playingStartID: UUID(), live: quick, stopFade: 0) { _ in true },
                       .crossfade(quick, fadeOut: AudioPlan.minimumCrossfade), "Never a click between tracks")
    }

    func testTheSameStartCarriesOnEvenPaused() {
        var live = LiveAudio(track: track)
        live.isPaused = true
        XCTAssertEqual(AudioPlan.decide(playingStartID: live.startID, live: live, stopFade: 0) { _ in false }, .keep,
                       "A track already playing isn't checked on disk again")
    }

    func testStoppingFadesOut() {
        XCTAssertEqual(AudioPlan.decide(playingStartID: UUID(), live: nil, stopFade: 1.5) { _ in true }, .fadeOut(1.5))
    }

    func testAMissingFileIsReported() {
        let live = LiveAudio(track: track)
        XCTAssertEqual(AudioPlan.decide(playingStartID: nil, live: live, stopFade: 0) { _ in false },
                       .missing(track.assetID))
    }

    func testFadeVolumeEasesFromStartToEnd() {
        XCTAssertEqual(AudioPlan.fadeVolume(from: 0, to: 1, elapsed: 0, duration: 2), 0)
        XCTAssertEqual(AudioPlan.fadeVolume(from: 0, to: 1, elapsed: 1, duration: 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AudioPlan.fadeVolume(from: 1, to: 0, elapsed: 2, duration: 2), 0)
        XCTAssertEqual(AudioPlan.fadeVolume(from: 1, to: 0, elapsed: 5, duration: 0), 0)
        XCTAssertLessThan(AudioPlan.fadeVolume(from: 0, to: 1, elapsed: 0.2, duration: 2), 0.1)
    }

    func testImportAudioCopiesAndDescribesItAndRejectsOtherFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Half a second of silence.
        let source = root.appendingPathComponent("tone.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050))
        buffer.frameLength = 22_050
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }
        let store = MediaStore(directory: root.appendingPathComponent("Media"))

        let asset = try await store.importAudio(at: source)
        XCTAssertEqual(asset.kind, .audio)
        XCTAssertEqual(asset.originalFilename, "tone.caf")
        XCTAssertEqual(try XCTUnwrap(asset.duration), 0.5, accuracy: 0.01)
        XCTAssertTrue(store.fileExists(for: asset))

        let text = root.appendingPathComponent("notes.txt")
        try Data("not audio".utf8).write(to: text)
        do {
            _ = try await store.importAudio(at: text)
            XCTFail("A text file isn't audio")
        } catch {
            XCTAssertEqual(error as? MediaImportError, .unplayableAudio)
        }
    }
}

@MainActor
final class AudioCommandTests: XCTestCase {
    /// A show of two presentations: A (two slides) and B (one slide), and two audio files and an image.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let a: PresentationDocument
        let b: PresentationDocument
        let itemA: PresentationItem
        let itemB: PresentationItem
        let music: MediaAsset
        let bells: MediaAsset
        let picture: MediaAsset

        @MainActor func take(_ item: PresentationItem, _ slide: Int) {
            let presentation = item.id == itemA.id ? a : b
            XCTAssertEqual(coordinator.takeLive(slideID: presentation.slides[slide].id, inItem: item.id), .applied)
        }
    }

    private func makeFixture() -> Fixture {
        let a = PresentationDocument(title: "A", slides: [.text("a1"), .text("a2")])
        let b = PresentationDocument(title: "B", slides: [.text("b1")])
        let itemA = PresentationItem(presentationID: a.id)
        let itemB = PresentationItem(presentationID: b.id)
        let music = MediaAsset(kind: .audio, originalFilename: "music.mp3", storedFilename: "m.mp3", pixelWidth: 0, pixelHeight: 0)
        let bells = MediaAsset(kind: .audio, originalFilename: "bells.wav", storedFilename: "b.wav", pixelWidth: 0, pixelHeight: 0)
        let picture = MediaAsset(originalFilename: "sky.jpg", storedFilename: "s.jpg", pixelWidth: 4, pixelHeight: 3)
        let project = ProjectDocument(name: "Test", presentations: [a, b],
                                      playlist: PlaylistDocument(title: "Service", items: [itemA, itemB]),
                                      mediaAssets: [music, bells, picture])
        return Fixture(coordinator: PresentationCoordinator(project: project), a: a, b: b, itemA: itemA, itemB: itemB,
                       music: music, bells: bells, picture: picture)
    }

    func testPlayPauseAndStopAreLiveAndNeverUndone() throws {
        let f = makeFixture()
        let c = f.coordinator
        XCTAssertEqual(c.playAudio(AudioTrack(assetID: f.music.id)), .applied)
        let first = try XCTUnwrap(c.state.audio)
        XCTAssertEqual(c.toggleAudioPause(), .applied)
        XCTAssertEqual(c.state.audio?.isPaused, true)
        XCTAssertEqual(c.toggleAudioPause(), .applied)
        XCTAssertEqual(c.state.audio?.isPaused, false)

        // Playing the same track again starts it from the top.
        c.playAudio(AudioTrack(assetID: f.music.id))
        XCTAssertNotEqual(c.state.audio?.startID, first.startID)

        XCTAssertEqual(c.stopAudio(fadeOut: 1), .applied)
        XCTAssertNil(c.state.audio)
        XCTAssertEqual(c.state.audioStopFade, 1)
        XCTAssertFalse(c.canUndo)
        XCTAssertEqual(c.stopAudio(), .rejected(.noAudio))
        XCTAssertEqual(c.toggleAudioPause(), .rejected(.noAudio))
    }

    func testOnlyAudioAssetsPlay() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.playAudio(AudioTrack(assetID: f.picture.id)), .rejected(.unknownMediaAsset))
        XCTAssertEqual(f.coordinator.playAudio(AudioTrack(assetID: UUID())), .rejected(.unknownMediaAsset))
        XCTAssertNil(f.coordinator.state.audio)
    }

    func testAFinishedTrackStopsUnlessAnotherReplacedIt() throws {
        let f = makeFixture()
        let c = f.coordinator
        c.playAudio(AudioTrack(assetID: f.music.id))
        let first = try XCTUnwrap(c.state.audio)
        c.playAudio(AudioTrack(assetID: f.bells.id))
        c.audioDidFinish(startID: first.startID)
        XCTAssertEqual(c.state.audio?.track.assetID, f.bells.id)
        c.audioDidFinish(startID: try XCTUnwrap(c.state.audio).startID)
        XCTAssertNil(c.state.audio)
    }

    func testSlideCuesPlayAndStopAndRetakingChangesNothing() throws {
        let f = makeFixture()
        let c = f.coordinator
        XCTAssertEqual(c.setAudioCue(.play(AudioTrack(assetID: f.music.id, fadeIn: 2)), slideID: f.a.slides[0].id,
                                     inPresentation: f.a.id), .applied)
        c.setAudioCue(.stop(fadeOut: 4), slideID: f.a.slides[1].id, inPresentation: f.a.id)

        f.take(f.itemA, 0)
        let started = try XCTUnwrap(c.state.audio)
        XCTAssertEqual(started.track, AudioTrack(assetID: f.music.id, fadeIn: 2))

        c.toggleAudioPause()
        f.take(f.itemA, 0)
        XCTAssertEqual(c.state.audio?.startID, started.startID, "Taking the same slide live again leaves the audio")
        XCTAssertEqual(c.state.audio?.isPaused, true)

        f.take(f.itemA, 1)
        XCTAssertNil(c.state.audio)
        XCTAssertEqual(c.state.audioStopFade, 4)
    }

    func testACueForTheTrackPlayingLetsItPlayOn() throws {
        let f = makeFixture()
        let c = f.coordinator
        let cue = AudioCue.play(AudioTrack(assetID: f.music.id))
        c.setAudioCue(cue, slideID: f.a.slides[0].id, inPresentation: f.a.id)
        c.setAudioCue(cue, slideID: f.a.slides[1].id, inPresentation: f.a.id)
        f.take(f.itemA, 0)
        let started = try XCTUnwrap(c.state.audio)
        f.take(f.itemA, 1)
        XCTAssertEqual(c.state.audio?.startID, started.startID)
    }

    func testASoundtrackStartsOnlyWhenMovingIntoThePresentation() throws {
        let f = makeFixture()
        let c = f.coordinator
        XCTAssertEqual(c.setSoundtrack(AudioTrack(assetID: f.bells.id, loops: true), presentationID: f.b.id), .applied)
        c.setSoundtrack(AudioTrack(assetID: f.music.id), presentationID: f.a.id)

        f.take(f.itemA, 0)
        XCTAssertEqual(c.state.audio?.track.assetID, f.music.id)
        c.stopAudio()
        f.take(f.itemA, 1)
        XCTAssertNil(c.state.audio, "Stopped by the operator, it stays stopped within the presentation")

        f.take(f.itemB, 0)
        let bells = try XCTUnwrap(c.state.audio)
        XCTAssertEqual(bells.track, AudioTrack(assetID: f.bells.id, loops: true))
    }

    func testASoundtrackAlreadyPlayingCarriesOnAndASlideCueWins() throws {
        let f = makeFixture()
        let c = f.coordinator
        c.setSoundtrack(AudioTrack(assetID: f.music.id), presentationID: f.a.id)
        c.setSoundtrack(AudioTrack(assetID: f.music.id), presentationID: f.b.id)
        f.take(f.itemA, 0)
        let started = try XCTUnwrap(c.state.audio)
        f.take(f.itemB, 0)
        XCTAssertEqual(c.state.audio?.startID, started.startID)

        c.setAudioCue(.play(AudioTrack(assetID: f.bells.id)), slideID: f.a.slides[1].id, inPresentation: f.a.id)
        f.take(f.itemA, 1)
        XCTAssertEqual(c.state.audio?.track.assetID, f.bells.id)
    }

    func testClearAllStopsAudioAndBlackoutDoesnt() {
        let f = makeFixture()
        let c = f.coordinator
        c.playAudio(AudioTrack(assetID: f.music.id))
        c.blackout()
        XCTAssertNotNil(c.state.audio)
        c.restoreOutput()
        XCTAssertEqual(c.clearAll(), .applied, "Audio alone is something to clear")
        XCTAssertNil(c.state.audio)
        XCTAssertEqual(c.state.audioStopFade, PresentationCoordinator.defaultAudioFadeOut)
    }

    func testCuesAndSoundtracksUndoAndRejectOtherMedia() {
        let f = makeFixture()
        let c = f.coordinator
        XCTAssertEqual(c.setSoundtrack(AudioTrack(assetID: f.picture.id), presentationID: f.a.id), .rejected(.unknownMediaAsset))
        XCTAssertEqual(c.setAudioCue(.play(AudioTrack(assetID: UUID())), slideID: f.a.slides[0].id, inPresentation: f.a.id),
                       .rejected(.unknownMediaAsset))
        XCTAssertFalse(c.canUndo)

        c.setSoundtrack(AudioTrack(assetID: f.music.id), presentationID: f.a.id)
        c.setAudioCue(.stop(fadeOut: 0), slideID: f.a.slides[0].id, inPresentation: f.a.id)
        c.undo()
        XCTAssertNil(c.project.presentation(withID: f.a.id)?.slides[0].audioCue)
        c.undo()
        XCTAssertNil(c.project.presentation(withID: f.a.id)?.soundtrack)
    }

    func testDeletingAudioMediaClearsCuesAndSoundtracks() {
        let f = makeFixture()
        let c = f.coordinator
        c.setSoundtrack(AudioTrack(assetID: f.music.id), presentationID: f.a.id)
        c.setAudioCue(.play(AudioTrack(assetID: f.music.id)), slideID: f.b.slides[0].id, inPresentation: f.b.id)
        c.setAudioCue(.stop(fadeOut: 2), slideID: f.a.slides[1].id, inPresentation: f.a.id)
        XCTAssertEqual(c.project.presentationsUsing(asset: f.music.id).map(\.id), [f.a.id, f.b.id])

        XCTAssertEqual(c.removeMediaAsset(f.music.id), .applied)
        XCTAssertNil(c.project.presentation(withID: f.a.id)?.soundtrack)
        XCTAssertNil(c.project.presentation(withID: f.b.id)?.slides[0].audioCue)
        XCTAssertEqual(c.project.presentation(withID: f.a.id)?.slides[1].audioCue, .stop(fadeOut: 2), "A stop cue uses no file")
    }

    func testAudioRoundTripsAndOlderFilesHaveNone() throws {
        let f = makeFixture()
        let c = f.coordinator
        c.setSoundtrack(AudioTrack(assetID: f.music.id, loops: true, fadeIn: 1.5), presentationID: f.a.id)
        c.setAudioCue(.play(AudioTrack(assetID: f.bells.id)), slideID: f.a.slides[0].id, inPresentation: f.a.id)
        c.setAudioCue(.stop(fadeOut: 3), slideID: f.a.slides[1].id, inPresentation: f.a.id)
        let data = try JSONEncoder().encode(c.project)
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: data), c.project)

        let json = #"{"id": "8E4B1C2A-0000-4000-8000-000000000003", "elements": []}"#
        XCTAssertNil(try JSONDecoder().decode(SlideDocument.self, from: Data(json.utf8)).audioCue)
        XCTAssertNil(f.b.soundtrack)
    }
}

final class AudioDeviceChoiceTests: XCTestCase {
    func testChosenDeviceWhileConnectedElseTheSystemOutput() {
        XCTAssertNil(AudioDeviceChoice.resolve(saved: nil, available: ["usb"]))
        XCTAssertEqual(AudioDeviceChoice.resolve(saved: "usb", available: ["built-in", "usb"]), "usb")
        XCTAssertNil(AudioDeviceChoice.resolve(saved: "usb", available: ["built-in"]), "Unplugged: the Mac's output")
        XCTAssertTrue(AudioDeviceChoice.isMissing(saved: "usb", available: ["built-in"]))
        XCTAssertFalse(AudioDeviceChoice.isMissing(saved: nil, available: []))
        XCTAssertFalse(AudioDeviceChoice.isMissing(saved: "usb", available: ["usb"]))
    }
}
