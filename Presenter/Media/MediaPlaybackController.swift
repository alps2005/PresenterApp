import AVFoundation
import AppKit
import Observation
import os
import PresenterCore
import SwiftUI

/// Plays the video on the audience output's background layer. It follows the live background, not any view,
/// so a video keeps playing (without restarting) while transparent slides change the words over it, and
/// windows can come and go without stopping it.
@Observable
final class MediaPlaybackController {
    /// The video playing now, if any.
    private(set) var assetID: UUID?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isMuted = true
    private(set) var loops = true
    /// The video played once to its end (it doesn't loop). Automatic advancing waits for this.
    private(set) var hasFinished = false
    var volume: Float = 1 {
        didSet { player.volume = volume }
    }

    @ObservationIgnored let player = AVQueuePlayer()
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private let coordinator: PresentationCoordinator
    @ObservationIgnored private let mediaLibrary: MediaLibrary
    @ObservationIgnored private let output: AudioOutput
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "Playback")

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary, output: AudioOutput) {
        self.coordinator = coordinator
        self.mediaLibrary = mediaLibrary
        self.output = output
        player.isMuted = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A looping item's time keeps counting; show where it is within the clip.
                self.currentTime = PlaybackPlan.clipTime(time.seconds, duration: self.duration)
                self.isPlaying = self.player.rate != 0
            }
        }
        follow()
        followDevice()
    }

    /// A video's sound goes to the chosen sound output too.
    private func followDevice() {
        let uid = withObservationTracking {
            output.effectiveUID
        } onChange: { [weak self] in
            Task { @MainActor in self?.followDevice() }
        }
        if player.audioOutputDeviceUniqueID != uid { player.audioOutputDeviceUniqueID = uid }
    }

    /// Watches the live background (and blackout) and keeps the player in step.
    private func follow() {
        let background = withObservationTracking {
            coordinator.state.liveBackground
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        sync(to: background)
    }

    private func sync(to background: SlideBackground?) {
        // The live background is the one source of truth for mute; the transport writes through the coordinator.
        if case .video(let video) = background {
            isMuted = video.isMuted
            player.isMuted = video.isMuted
        }
        let decision = PlaybackPlan.decide(playingAssetID: assetID, playingLoops: loops, background: background) { id in
            coordinator.project.asset(withID: id).map { mediaLibrary.store.fileExists(for: $0) } ?? false
        }
        switch decision {
        case .stop:
            stop()
        case .keep:
            break
        case .load(let video), .reload(let video):
            load(video)
        case .missing(let id):
            stop()
            mediaLibrary.markMissing(id)
            logger.error("Video missing: \(id, privacy: .public)")
        }
    }

    private func load(_ video: VideoBackground) {
        guard let asset = coordinator.project.asset(withID: video.assetID) else { return stop() }
        stop()
        let item = AVPlayerItem(url: mediaLibrary.store.url(for: asset))
        assetID = video.assetID
        loops = video.loops
        duration = asset.duration ?? 0
        if video.loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isPlaying = false
                    self?.hasFinished = true
                }
            }
        }
        player.play()
        isPlaying = true
    }

    private func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        assetID = nil
        isPlaying = false
        hasFinished = false
        currentTime = 0
        duration = 0
    }

    // MARK: Transport

    func togglePlay() {
        if player.rate != 0 {
            player.pause()
        } else {
            // A finished, non-looping video starts again from the top.
            if let item = player.currentItem,
               PlaybackPlan.restartsFromTop(loops: loops, currentTime: item.currentTime().seconds, duration: item.duration.seconds) {
                item.seek(to: .zero, completionHandler: nil)
            }
            player.play()
            hasFinished = false
        }
        isPlaying = player.rate != 0
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        if seconds < duration { hasFinished = false }
    }

    /// Mutes through the coordinator, so the setting lives in the live background and survives slide changes.
    func toggleMute() {
        coordinator.setLiveVideoMuted(!isMuted)
    }
}

/// Shows the playing video, sharing the one player, so the audience output and the operator's preview match.
struct VideoPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    let scaling: ImageScaling

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
    }

    private var gravity: AVLayerVideoGravity {
        switch scaling {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        }
    }

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
            playerLayer.backgroundColor = NSColor.black.cgColor
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }
}
