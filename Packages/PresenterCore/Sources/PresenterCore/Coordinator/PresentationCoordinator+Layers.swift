import Foundation

// The layers over and under the live slide: media cues on the background layer, messages and props. Never undone.
extension PresentationCoordinator {
    // MARK: - Media (live: never undone)

    /// Puts an image, video or colour straight onto the audience output's background layer, like clicking a
    /// cue in ProPresenter's media bin. The words on screen stay. Transparent slides keep it; the next
    /// opaque slide replaces it.
    @discardableResult
    public func showBackground(_ background: SlideBackground) -> CommandResult {
        if let rejection = validate(background) { return reject(rejection) }
        guard background != .transparent else { return reject(.nothingToClear) }
        state.liveBackground = background
        state.clearedBackground = nil
        Log.coordinator.info("Media cue on the background layer")
        return applied()
    }

    /// Mutes or unmutes the video on the background layer. The live background is the one source of truth for
    /// playback, so the setting holds while transparent slides change over the video, and when the next slide
    /// keeps playing the same video.
    @discardableResult
    public func setLiveVideoMuted(_ isMuted: Bool) -> CommandResult {
        guard case .video(var video) = state.liveBackground else { return reject(.nothingLive) }
        video.isMuted = isMuted
        state.liveBackground = .video(video)
        return applied()
    }

    // MARK: - Messages and props (live: never undone)

    /// Shows a message over the slides, replacing any other message.
    @discardableResult
    public func showMessage(_ messageID: UUID, values: [String: String] = [:]) -> CommandResult {
        guard project.message(withID: messageID) != nil else { return reject(.unknownMessage) }
        state.activeMessage = ActiveMessage(messageID: messageID, values: values)
        state.clearedMessage = nil
        return applied()
    }

    /// Clear Messages.
    @discardableResult
    public func clearMessages() -> CommandResult {
        guard let active = state.activeMessage else { return reject(.nothingToClear) }
        state.clearedMessage = active
        state.activeMessage = nil
        return applied()
    }

    /// Shows a prop if hidden, hides it if shown. Several props can be on screen at once.
    @discardableResult
    public func toggleProp(_ propID: UUID) -> CommandResult {
        guard let prop = project.prop(withID: propID) else { return reject(.unknownProp) }
        if state.activeProps.contains(propID) {
            state.activeProps.removeAll { $0 == propID }
            state.propSnapshots[propID] = nil
        } else {
            state.activeProps.append(propID)
            state.propSnapshots[propID] = prop
            for cleared in state.clearedProps where !state.activeProps.contains(cleared) {
                state.propSnapshots[cleared] = nil
            }
            state.clearedProps = []
        }
        return applied()
    }

    /// Clear Props.
    @discardableResult
    public func clearProps() -> CommandResult {
        guard !state.activeProps.isEmpty else { return reject(.nothingToClear) }
        state.clearedProps = state.activeProps
        state.activeProps = []
        return applied()
    }
}
