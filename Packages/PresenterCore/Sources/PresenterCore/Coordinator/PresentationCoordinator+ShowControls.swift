import Foundation

// Timers and the stage message (live), and the message, prop, timer and stage libraries (undoable edits).
extension PresentationCoordinator {
    // MARK: - Timers and stage (live: never undone)

    public func timer(withID timerID: UUID) -> TimerDefinition? {
        project.timers.first { $0.id == timerID }
    }

    public func timerRun(for timerID: UUID) -> TimerRun {
        timerRuns[timerID] ?? TimerRun()
    }

    /// The timer's value at `date` (see `TimerDefinition.seconds`), or nil if it doesn't exist.
    public func timerSeconds(_ timerID: UUID, at date: Date) -> Int? {
        timer(withID: timerID).map { $0.seconds(run: timerRun(for: timerID), now: date) }
    }

    /// Starts or resumes a timer.
    @discardableResult
    public func startTimer(_ timerID: UUID) -> CommandResult {
        guard timer(withID: timerID) != nil else { return reject(.unknownTimer) }
        var run = timerRun(for: timerID)
        if !run.isRunning { run.startedAt = now() }
        timerRuns[timerID] = run
        return applied()
    }

    /// Pauses a timer, keeping its time.
    @discardableResult
    public func stopTimer(_ timerID: UUID) -> CommandResult {
        guard timer(withID: timerID) != nil else { return reject(.unknownTimer) }
        let run = timerRun(for: timerID)
        timerRuns[timerID] = TimerRun(startedAt: nil, accumulated: run.elapsed(at: now()))
        return applied()
    }

    /// Stops a timer and returns it to its starting value.
    @discardableResult
    public func resetTimer(_ timerID: UUID) -> CommandResult {
        guard timer(withID: timerID) != nil else { return reject(.unknownTimer) }
        timerRuns[timerID] = nil
        return applied()
    }

    /// Shows a message on the stage display only. Empty text hides it.
    @discardableResult
    public func showStageMessage(_ text: String) -> CommandResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        state.stageMessage = trimmed.isEmpty ? nil : trimmed
        return applied()
    }

    @discardableResult
    public func hideStageMessage() -> CommandResult {
        state.stageMessage = nil
        return applied()
    }

    // MARK: - Message and prop library (edits: undoable)

    @discardableResult
    public func addMessage(name: String, text: String) -> MessageDefinition {
        addMessage(MessageDefinition(name: name, text: text))
    }

    /// Adds a message with all its settings (position, size, colours) as one undoable step.
    @discardableResult
    public func addMessage(_ definition: MessageDefinition) -> MessageDefinition {
        recordingUndo("Add Message") {
            var message = definition
            if message.name.isEmpty { message.name = "Message" }
            project.messages.append(message)
            lastRejection = nil
            return message
        }
    }

    @discardableResult
    public func updateMessage(_ message: MessageDefinition) -> CommandResult {
        recordingUndo("Edit Message", coalescing: "message-\(message.id)") {
            guard let index = project.messages.firstIndex(where: { $0.id == message.id }) else { return reject(.unknownMessage) }
            project.messages[index] = message
            return applied()
        }
    }

    /// Deleting the message on screen leaves the output alone until it's cleared.
    @discardableResult
    public func deleteMessage(_ messageID: UUID) -> CommandResult {
        recordingUndo("Delete Message") {
            guard project.messages.contains(where: { $0.id == messageID }) else { return reject(.unknownMessage) }
            project.messages.removeAll { $0.id == messageID }
            return applied()
        }
    }

    /// Adds a prop with a text box, ready to edit in the slide editor.
    @discardableResult
    public func addProp(name: String) -> SlideDocument {
        recordingUndo("Add Prop") {
            var prop = SlideDocument(
                elements: [.text(TextElement(text: name.isEmpty ? "Prop" : name, role: .caption,
                                             box: TextBox(frame: .centered(width: 0.4, height: 0.15))))],
                background: .transparent
            )
            prop.label = name.isEmpty ? "Prop" : name
            project.props.slides.append(prop)
            lastRejection = nil
            return prop
        }
    }

    @discardableResult
    public func renameProp(_ propID: UUID, to name: String) -> CommandResult {
        recordingUndo("Rename Prop", coalescing: "prop-name-\(propID)") {
            guard let index = project.props.index(ofSlide: propID) else { return reject(.unknownProp) }
            project.props.slides[index].label = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
            return applied()
        }
    }

    /// Deleting a prop that's on screen takes it off.
    @discardableResult
    public func deleteProp(_ propID: UUID) -> CommandResult {
        recordingUndo("Delete Prop") {
            guard project.props.index(ofSlide: propID) != nil else { return reject(.unknownProp) }
            project.props.slides.removeAll { $0.id == propID }
            state.activeProps.removeAll { $0 == propID }
            state.clearedProps.removeAll { $0 == propID }
            state.propSnapshots[propID] = nil
            return applied()
        }
    }

    // MARK: - Timer and stage settings (edits: undoable)

    @discardableResult
    public func addTimer(name: String, kind: TimerDefinition.Kind) -> TimerDefinition {
        recordingUndo("Add Timer") {
            let timer = TimerDefinition(name: name.isEmpty ? "Timer" : name, kind: kind)
            project.timers.append(timer)
            lastRejection = nil
            return timer
        }
    }

    /// Changing a timer's kind or duration resets it.
    @discardableResult
    public func updateTimer(_ timer: TimerDefinition) -> CommandResult {
        recordingUndo("Edit Timer", coalescing: "timer-\(timer.id)") {
            guard let index = project.timers.firstIndex(where: { $0.id == timer.id }) else { return reject(.unknownTimer) }
            if project.timers[index].kind != timer.kind { timerRuns[timer.id] = nil }
            project.timers[index] = timer
            return applied()
        }
    }

    @discardableResult
    public func deleteTimer(_ timerID: UUID) -> CommandResult {
        recordingUndo("Delete Timer") {
            guard project.timers.contains(where: { $0.id == timerID }) else { return reject(.unknownTimer) }
            project.timers.removeAll { $0.id == timerID }
            if project.stage.timerID == timerID { project.stage.timerID = nil }
            timerRuns[timerID] = nil
            return applied()
        }
    }

    @discardableResult
    public func setStageSettings(_ settings: StageSettings) -> CommandResult {
        recordingUndo("Stage Settings") {
            if let timerID = settings.timerID, timer(withID: timerID) == nil { return reject(.unknownTimer) }
            project.stage = settings
            return applied()
        }
    }
}
