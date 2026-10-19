import AVFoundation
import Observation
import os
import PresenterCore

/// Plays the live audio: tracks from the audio bin, slide audio cues and soundtracks. It follows the coordinator's
/// live audio, not any view, like the video player follows the live background. Each track has its own player, so
/// one can fade out while the next fades in.
@Observable
final class AudioPlaybackController {
    /// The track playing now, if any, and where it is.
    private(set) var assetID: UUID?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused = false
    /// A track that couldn't play because its file is gone, until another starts.
    private(set) var missingAssetID: UUID?

    @ObservationIgnored private var current: Track?
    /// Tracks fading out after a stop or a change of track.
    @ObservationIgnored private var fadingOut: [Track] = []
    @ObservationIgnored private var rampTimer: Timer?
    @ObservationIgnored private let coordinator: PresentationCoordinator
    @ObservationIgnored private let mediaLibrary: MediaLibrary
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.alps2005.Presenter", category: "Audio")

    /// Volume ramps step 30 times a second: smooth to the ear, and cheap.
    private static let rampInterval: TimeInterval = 1.0 / 30

    init(coordinator: PresentationCoordinator, mediaLibrary: MediaLibrary) {
        self.coordinator = coordinator
        self.mediaLibrary = mediaLibrary
        follow()
    }

    /// Watches the live audio and keeps the players in step.
    private func follow() {
        let live = withObservationTracking {
            coordinator.state.audio
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        sync(to: live)
    }

    private func sync(to live: LiveAudio?) {
        let decision = AudioPlan.decide(playingStartID: current?.startID, live: live,
                                        stopFade: coordinator.state.audioStopFade) { id in
            coordinator.project.asset(withID: id).map { mediaLibrary.store.fileExists(for: $0) } ?? false
        }
        switch decision {
        case .idle:
            break
        case .keep:
            if let live { setPaused(live.isPaused) }
        case .start(let live):
            start(live)
        case .crossfade(let live, let fadeOut):
            fadeOutCurrent(over: fadeOut)
            start(live)
        case .fadeOut(let seconds):
            fadeOutCurrent(over: seconds)
        case .missing(let id):
            fadeOutCurrent(over: AudioPlan.minimumCrossfade)
            missingAssetID = id
            logger.error("Audio missing: \(id, privacy: .public)")
            if let live { coordinator.audioDidFinish(startID: live.startID) }
        }
    }

    private func start(_ live: LiveAudio) {
        guard let asset = coordinator.project.asset(withID: live.track.assetID) else { return }
        let track = Track(live: live, url: mediaLibrary.store.url(for: asset), duration: asset.duration ?? 0) { [weak self] time in
            self?.currentTime = time
        } onEnd: { [weak self] in
            self?.coordinator.audioDidFinish(startID: live.startID)
        }
        current = track
        assetID = asset.id
        duration = asset.duration ?? 0
        currentTime = 0
        missingAssetID = nil
        isPaused = live.isPaused
        if live.track.fadeIn > 0 {
            track.fade(to: 1, over: live.track.fadeIn)
        } else {
            track.player.volume = 1
        }
        if !live.isPaused { track.player.play() }
        startRampingIfNeeded()
        logger.info("Playing \(asset.originalFilename, privacy: .public)")
    }

    private func fadeOutCurrent(over seconds: Double) {
        guard let track = current else { return }
        current = nil
        assetID = nil
        currentTime = 0
        duration = 0
        isPaused = false
        guard seconds > 0, track.player.rate != 0 else { return track.stop() }
        track.fade(to: 0, over: seconds)
        fadingOut.append(track)
        startRampingIfNeeded()
    }

    private func setPaused(_ paused: Bool) {
        guard let track = current, paused != isPaused else { return }
        isPaused = paused
        if paused { track.player.pause() } else { track.player.play() }
    }

    private func startRampingIfNeeded() {
        guard rampTimer == nil, current?.isFading == true || !fadingOut.isEmpty else { return }
        rampTimer = Timer.scheduledTimer(withTimeInterval: Self.rampInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.ramp() }
        }
    }

    private func ramp() {
        let now = Date()
        current?.step(at: now)
        for track in fadingOut { track.step(at: now) }
        fadingOut.removeAll { track in
            guard !track.isFading else { return false }
            track.stop()
            return true
        }
        if current?.isFading != true, fadingOut.isEmpty {
            rampTimer?.invalidate()
            rampTimer = nil
        }
    }

    // MARK: Transport

    func togglePause() {
        coordinator.toggleAudioPause()
    }

    func stop() {
        coordinator.stopAudio()
    }

    func seek(to seconds: Double) {
        current?.player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
}

/// One playing file, with its own player so it can fade on its own.
private final class Track {
    let startID: UUID
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var fade: (from: Float, to: Float, start: Date, duration: Double)?

    var isFading: Bool { fade != nil }

    init(live: LiveAudio, url: URL, duration: Double, onTime: @escaping @MainActor (Double) -> Void,
         onEnd: @escaping @MainActor () -> Void) {
        startID = live.startID
        let item = AVPlayerItem(url: url)
        player.volume = 0
        if live.track.loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                MainActor.assumeIsolated { onEnd() }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { time in
            // A looping item's time keeps counting; show where it is within the file.
            MainActor.assumeIsolated { onTime(PlaybackPlan.clipTime(time.seconds, duration: duration)) }
        }
    }

    func fade(to volume: Float, over seconds: Double) {
        fade = (player.volume, volume, Date(), seconds)
    }

    func step(at date: Date) {
        guard let fade else { return }
        let elapsed = date.timeIntervalSince(fade.start)
        player.volume = Float(AudioPlan.fadeVolume(from: Double(fade.from), to: Double(fade.to), elapsed: elapsed,
                                                   duration: fade.duration))
        if elapsed >= fade.duration { self.fade = nil }
    }

    func stop() {
        fade = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
