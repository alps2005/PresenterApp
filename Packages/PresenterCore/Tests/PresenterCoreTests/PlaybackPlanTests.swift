import Foundation
import XCTest
@testable import PresenterCore

final class PlaybackPlanTests: XCTestCase {
    private let clip = UUID()
    private let other = UUID()

    private func decide(playing: UUID?, loops: Bool = true, _ background: SlideBackground?, exists: Bool = true) -> PlaybackDecision {
        PlaybackPlan.decide(playingAssetID: playing, playingLoops: loops, background: background) { _ in exists }
    }

    func testNoVideoStops() {
        XCTAssertEqual(decide(playing: clip, nil), .stop)
        XCTAssertEqual(decide(playing: clip, .color(.black)), .stop)
        XCTAssertEqual(decide(playing: nil, .image(ImageBackground(assetID: clip))), .stop)
    }

    func testTheSameVideoKeepsPlayingEvenWithOtherSettingsChanged() {
        let video = VideoBackground(assetID: clip, scaling: .fit, isMuted: false, dimming: 0.4)
        XCTAssertEqual(decide(playing: clip, .video(video)), .keep)
    }

    func testChangingLoopReloads() {
        let video = VideoBackground(assetID: clip, loops: false)
        XCTAssertEqual(decide(playing: clip, loops: true, .video(video)), .reload(video))
    }

    func testANewVideoLoadsOrIsReportedMissing() {
        let video = VideoBackground(assetID: other)
        XCTAssertEqual(decide(playing: clip, .video(video)), .load(video))
        XCTAssertEqual(decide(playing: nil, .video(video), exists: false), .missing(other))
    }

    func testFileIsCheckedOnlyForANewVideo() {
        var asked: [UUID] = []
        _ = PlaybackPlan.decide(playingAssetID: clip, playingLoops: true, background: .video(VideoBackground(assetID: clip))) {
            asked.append($0)
            return false
        }
        XCTAssertEqual(asked, [])
    }

    func testClipTimeWrapsALoopingPlayersTime() {
        XCTAssertEqual(PlaybackPlan.clipTime(25, duration: 10), 5, accuracy: 1e-9)
        XCTAssertEqual(PlaybackPlan.clipTime(3, duration: 10), 3, accuracy: 1e-9)
        XCTAssertEqual(PlaybackPlan.clipTime(5, duration: 0), 0)
        XCTAssertEqual(PlaybackPlan.clipTime(.nan, duration: 10), 0)
    }

    func testOnlyAFinishedNonLoopingVideoRestartsFromTheTop() {
        XCTAssertTrue(PlaybackPlan.restartsFromTop(loops: false, currentTime: 10, duration: 10))
        XCTAssertFalse(PlaybackPlan.restartsFromTop(loops: false, currentTime: 4, duration: 10))
        XCTAssertFalse(PlaybackPlan.restartsFromTop(loops: true, currentTime: 10, duration: 10))
        XCTAssertFalse(PlaybackPlan.restartsFromTop(loops: false, currentTime: 10, duration: .nan))
    }
}
