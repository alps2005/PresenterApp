import Foundation

// Automatic advancing, like ProPresenter: a presentation's Slideshow interval and each slide's Go To Next timer move
// the live slide on by themselves. Setting them is an edit (undoable); the countdown itself is live state.
extension PresentationCoordinator {
    /// The shortest countdown, so a run of 0-second slides can't spin.
    static let minimumAdvanceDelay: TimeInterval = 0.25
    /// The shortest Slideshow interval.
    static let minimumSlideshowInterval: Double = 1

    // MARK: - Editing

    /// Gives slides of one presentation a Go To Next timer, or with nil removes it. A live slide among them starts
    /// its countdown again with the new time.
    @discardableResult
    public func setGoToNext(_ timer: GoToNextTimer?, forSlides slideIDs: [UUID], inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Go To Next Timer") {
            guard let presentation = project.presentation(withID: presentationID) else { return reject(.unknownPresentation) }
            guard !slideIDs.isEmpty, slideIDs.allSatisfy({ presentation.slide(withID: $0) != nil }) else {
                return reject(.unknownSlide)
            }
            var timer = timer
            if let seconds = timer?.seconds { timer?.seconds = max(0, seconds) }
            let result = editPresentation(presentationID) { presentation in
                for index in presentation.slides.indices where slideIDs.contains(presentation.slides[index].id) {
                    presentation.slides[index].goToNext = timer
                }
            }
            restartAutoAdvance(ifLiveIn: presentationID)
            return result
        }
    }

    /// Turns a presentation's Slideshow on with an interval in seconds, or off with nil.
    @discardableResult
    public func setSlideshowInterval(_ seconds: Double?, presentation presentationID: UUID) -> CommandResult {
        recordingUndo("Slideshow") {
            let interval = seconds.map { max(Self.minimumSlideshowInterval, $0) }
            let result = editPresentation(presentationID) { $0.slideshowInterval = interval }
            restartAutoAdvance(ifLiveIn: presentationID)
            return result
        }
    }

    // MARK: - Live

    /// Stops the live slide's countdown. The next slide taken live starts its own.
    @discardableResult
    public func stopAutoAdvance() -> CommandResult {
        guard state.autoAdvance != nil else { return reject(.autoAdvanceOff) }
        state.autoAdvance = nil
        Log.coordinator.info("Auto-advance stopped")
        return applied()
    }

    /// Moves the live slide on if its countdown is over. The app calls it when the deadline comes. Returns whether
    /// the slide moved; when there's nowhere to go (the end of the show), the countdown just ends.
    @discardableResult
    public func advanceIfDue() -> Bool {
        guard let advance = state.autoAdvance, case .counting(_, let deadline) = advance.phase, now() >= deadline else {
            return false
        }
        guard let live = state.live, live.position == advance.position, !state.isBlackout,
              let next = autoAdvanceTarget(from: live.position) else {
            state.autoAdvance = nil
            return false
        }
        return goLive(at: next).isApplied
    }

    /// The live slide's video, which plays once, has ended (or can't play): its countdown starts now.
    public func videoDidFinish(_ assetID: UUID) {
        guard var advance = state.autoAdvance, advance.phase == .waitingForVideo(assetID: assetID) else { return }
        advance.phase = countingPhase(seconds: advance.seconds)
        state.autoAdvance = advance
    }

    // MARK: - Helpers

    /// Starts the countdown for a slide that just went live, or clears it when the slide doesn't move on by itself.
    /// A slide that brings a video playing once waits for the video to end; a looping video doesn't hold it up.
    func startAutoAdvance(for live: LiveSlide) {
        guard let seconds = autoAdvanceSeconds(at: live.position) else {
            state.autoAdvance = nil
            return
        }
        let phase: AutoAdvance.Phase
        if case .video(let video) = live.rendered.background, !video.loops {
            phase = .waitingForVideo(assetID: video.assetID)
        } else {
            phase = countingPhase(seconds: seconds)
        }
        state.autoAdvance = AutoAdvance(position: live.position, seconds: seconds, phase: phase)
    }

    /// The slide's own Go To Next time, else its presentation's Slideshow interval.
    func autoAdvanceSeconds(at position: SlidePosition) -> Double? {
        guard let presentation = project.presentation(forItem: position.itemID),
              let slide = presentation.slide(withID: position.slideID) else { return nil }
        return slide.goToNext?.seconds ?? presentation.slideshowInterval
    }

    /// Where the live slide moves on to: the presentation's first slide for a Go To Next timer that loops, else
    /// the next slide in the show, as → does (none at the end of the show). A Slideshow stays in its presentation,
    /// going back to the first slide after the last.
    func autoAdvanceTarget(from position: SlidePosition) -> SlidePosition? {
        guard let presentation = project.presentation(forItem: position.itemID),
              let slide = presentation.slide(withID: position.slideID) else { return nil }
        let itemSlides = presentation.arrangedSlides.map {
            SlidePosition(itemID: position.itemID, slideID: $0.slideID, occurrence: $0.occurrence)
        }
        if let timer = slide.goToNext {
            if timer.loopsToFirst { return itemSlides.first }
            let sequence = slideSequence()
            guard let index = Self.index(of: position, in: sequence), sequence.indices.contains(index + 1) else { return nil }
            return sequence[index + 1]
        }
        guard presentation.slideshowInterval != nil, let index = Self.index(of: position, in: itemSlides) else { return nil }
        return itemSlides[(index + 1) % itemSlides.count]
    }

    /// After a timer edit, the live slide's countdown starts again if the slide is in that presentation.
    private func restartAutoAdvance(ifLiveIn presentationID: UUID) {
        guard let live = state.live, !state.isBlackout,
              project.presentation(forItem: live.position.itemID)?.id == presentationID else { return }
        startAutoAdvance(for: live)
    }

    private func countingPhase(seconds: Double) -> AutoAdvance.Phase {
        let start = now()
        return .counting(started: start, deadline: start.addingTimeInterval(max(seconds, Self.minimumAdvanceDelay)))
    }
}
