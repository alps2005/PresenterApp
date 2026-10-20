import Foundation

// Slide actions and macros. Running them is live, so never undone; editing them is undoable.
extension PresentationCoordinator {
    /// How deep macros may run other macros, so two that run each other stop.
    static let macroNestingLimit = 4

    // MARK: - Running (live)

    /// Runs a macro's actions, in order.
    @discardableResult
    public func runMacro(_ macroID: UUID) -> CommandResult {
        guard let macro = project.macro(withID: macroID) else { return reject(.unknownMacro) }
        run(macro.actions, depth: 1)
        Log.coordinator.info("Ran macro \(macroID, privacy: .public)")
        return applied()
    }

    /// Runs the actions of a slide just taken live. Taking the same slide live again doesn't run them again, as with
    /// its audio cue.
    func runSlideActions(at position: SlidePosition, after previous: SlidePosition?) {
        guard position != previous, let slide = project.slide(at: position), !slide.actions.isEmpty else { return }
        run(slide.actions.filter(\.isAllowedOnSlides), depth: 0)
    }

    /// Carries out actions one by one. One that can't (a timer that's gone, nothing to clear) is passed over, without
    /// a warning: the slide or macro still did the rest.
    func run(_ actions: [ShowAction], depth: Int) {
        for action in actions { perform(action, depth: depth) }
    }

    private func perform(_ action: ShowAction, depth: Int) {
        switch action {
        case .startTimer(let timerID): startTimer(timerID)
        case .stopTimer(let timerID): stopTimer(timerID)
        case .resetTimer(let timerID): resetTimer(timerID)
        case .restartTimer(let timerID):
            resetTimer(timerID)
            startTimer(timerID)
        case .showMessage(let messageID, let values): showMessage(messageID, values: values)
        case .clearMessages: if state.activeMessage != nil { clearMessages() }
        case .showProp(let propID): if !state.activeProps.contains(propID) { toggleProp(propID) }
        case .hideProp(let propID): if state.activeProps.contains(propID) { toggleProp(propID) }
        case .clearProps: if !state.activeProps.isEmpty { clearProps() }
        case .showStageMessage(let text): showStageMessage(text)
        case .hideStageMessage: hideStageMessage()
        case .setStageLayout(let layoutID):
            guard layoutID.map({ project.stageLayout(withID: $0) != nil }) ?? true else { return }
            state.stageLayoutOverride = StageLayoutOverride(layoutID: layoutID)
        case .playAudio(let track): if project.asset(withID: track.assetID)?.kind == .audio { playAudio(track) }
        case .stopAudio: if state.audio != nil { stopAudio() }
        case .clearSlide: if state.live != nil { clearOutput() }
        case .clearBackground: if state.liveBackground != nil { clearBackground() }
        case .clearAll: clearAll()
        case .blackout: blackout()
        case .runMacro(let macroID):
            guard depth < Self.macroNestingLimit, let macro = project.macro(withID: macroID) else { return }
            run(macro.actions, depth: depth + 1)
        }
    }

    // MARK: - Editing (undoable)

    /// Sets what a slide does when it's taken live.
    @discardableResult
    public func setSlideActions(_ actions: [ShowAction], slideID: UUID, inPresentation presentationID: UUID) -> CommandResult {
        recordingUndo("Slide Actions", coalescing: "slide-actions-\(slideID)") {
            editSlide(slideID, inPresentation: presentationID) { $0.actions = actions.filter(\.isAllowedOnSlides) }
        }
    }

    /// Adds an empty macro and returns it.
    @discardableResult
    public func addMacro(named name: String) -> Macro {
        recordingUndo("New Macro") {
            let macro = Macro(name: name.isEmpty ? "Untitled Macro" : name)
            project.macros.append(macro)
            lastRejection = nil
            return macro
        }
    }

    /// Saves a changed macro: its name, colour or actions. Typing a name undoes in one step.
    @discardableResult
    public func updateMacro(_ macro: Macro) -> CommandResult {
        recordingUndo("Edit Macro", coalescing: "macro-\(macro.id)") {
            guard let index = project.macros.firstIndex(where: { $0.id == macro.id }) else { return reject(.unknownMacro) }
            project.macros[index] = macro
            return applied()
        }
    }

    /// Copies a macro, placing the copy after it.
    @discardableResult
    public func duplicateMacro(_ macroID: UUID) -> Macro? {
        guard let index = project.macros.firstIndex(where: { $0.id == macroID }) else {
            _ = reject(.unknownMacro)
            return nil
        }
        return recordingUndo("Duplicate Macro") {
            let source = project.macros[index]
            let copy = Macro(name: "\(source.name) Copy", color: source.color, actions: source.actions)
            project.macros.insert(copy, at: index + 1)
            lastRejection = nil
            return copy
        }
    }

    /// Deletes a macro. Slides and macros that ran it do nothing in its place.
    @discardableResult
    public func deleteMacro(_ macroID: UUID) -> CommandResult {
        recordingUndo("Delete Macro") {
            guard project.macro(withID: macroID) != nil else { return reject(.unknownMacro) }
            project.macros.removeAll { $0.id == macroID }
            return applied()
        }
    }
}
