import Foundation

extension PresentationState {
    /// Whether something is reaching the audience or the stage: a slide, background, message, prop, stage message,
    /// a blackout or a track. Presenter never interrupts the operator then: an update waits, and doesn't even ask.
    ///
    /// - Parameter outputsShowing: whether an audience output or stage display window is on screen. That counts as
    ///   presenting even with nothing live (between songs, the default background is still on the wall).
    public func isPresenting(outputsShowing: Bool) -> Bool {
        outputsShowing
            || live != nil
            || liveBackground != nil
            || activeMessage != nil
            || !activeProps.isEmpty
            || stageMessage != nil
            || isBlackout
            || audio != nil
    }
}
