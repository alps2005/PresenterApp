import Foundation

// Live commands: cue, take live, next/previous, clear, blackout and restore. Never undone.
extension PresentationCoordinator {
    // MARK: - Live commands

    @discardableResult
    public func selectItem(_ itemID: UUID) -> CommandResult {
        guard project.playlist.item(withID: itemID) != nil else { return reject(.unknownItem) }
        state.selectedItemID = itemID
        return applied()
    }

    /// Cues a slide for preview. Never changes the audience output.
    @discardableResult
    public func cueSlide(_ slideID: UUID, inItem itemID: UUID, occurrence: Int = 0) -> CommandResult {
        let position = SlidePosition(itemID: itemID, slideID: slideID, occurrence: occurrence)
        guard project.playlist.item(withID: itemID) != nil else { return reject(.unknownItem) }
        guard project.slide(at: position) != nil else { return reject(.unknownSlide) }
        state.selectedItemID = itemID
        state.preview = position
        return applied()
    }

    /// Sends the cued slide to the audience output. Blackout, if active, stays active.
    @discardableResult
    public func takeLive() -> CommandResult {
        guard let preview = state.preview else { return reject(.nothingCued) }
        return goLive(at: preview)
    }

    /// Cues and takes a slide live in one step (e.g. double-click).
    @discardableResult
    public func takeLive(slideID: UUID, inItem itemID: UUID, occurrence: Int = 0) -> CommandResult {
        let result = cueSlide(slideID, inItem: itemID, occurrence: occurrence)
        guard result.isApplied else { return result }
        return takeLive()
    }

    @discardableResult
    public func nextSlide() -> CommandResult {
        step(by: 1, boundary: .atEndOfPlaylist)
    }

    @discardableResult
    public func previousSlide() -> CommandResult {
        step(by: -1, boundary: .atStartOfPlaylist)
    }

    /// Removes the live slide from the audience output, leaving the empty background.
    @discardableResult
    /// Clear Slide: removes the live slide's words and elements. The background layer stays, as in ProPresenter.
    public func clearOutput() -> CommandResult {
        guard let live = state.live else { return reject(.nothingLive) }
        state.cleared = live
        state.live = nil
        Log.coordinator.info("Slide cleared")
        return applied()
    }

    /// Clear Background: removes the background layer, back to the app's default. The live slide stays.
    @discardableResult
    public func clearBackground() -> CommandResult {
        guard let background = state.liveBackground else { return reject(.nothingToClear) }
        state.clearedBackground = background
        state.liveBackground = nil
        Log.coordinator.info("Background cleared")
        return applied()
    }

    /// Clear All: removes the slide and the background.
    @discardableResult
    public func clearAll() -> CommandResult {
        guard state.live != nil || state.liveBackground != nil || state.activeMessage != nil || !state.activeProps.isEmpty else {
            return reject(.nothingLive)
        }
        if state.live != nil { _ = clearOutput() }
        if state.liveBackground != nil { _ = clearBackground() }
        if state.activeMessage != nil { _ = clearMessages() }
        if !state.activeProps.isEmpty { _ = clearProps() }
        return applied()
    }

    // MARK: - Blackout and restore

    @discardableResult
    public func blackout() -> CommandResult {
        state.isBlackout = true
        Log.coordinator.info("Blackout on")
        return applied()
    }

    /// Lifts blackout and brings back a cleared slide, if any.
    @discardableResult
    public func restoreOutput() -> CommandResult {
        var changed = false
        if state.isBlackout {
            state.isBlackout = false
            changed = true
        }
        if state.live == nil, let cleared = state.cleared {
            state.live = cleared
            state.cleared = nil
            changed = true
        }
        if state.liveBackground == nil, let background = state.clearedBackground {
            state.liveBackground = background
            state.clearedBackground = nil
            changed = true
        }
        if state.activeMessage == nil, let message = state.clearedMessage {
            state.activeMessage = message
            state.clearedMessage = nil
            changed = true
        }
        if state.activeProps.isEmpty, !state.clearedProps.isEmpty {
            state.activeProps = state.clearedProps
            state.clearedProps = []
            changed = true
        }
        guard changed else { return reject(.nothingToRestore) }
        Log.coordinator.info("Output restored")
        return applied()
    }
}
