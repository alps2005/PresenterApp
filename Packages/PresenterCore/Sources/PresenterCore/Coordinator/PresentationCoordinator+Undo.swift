import Foundation

// The undo engine, and swapping in a different project.
extension PresentationCoordinator {
    // MARK: - Undo

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// What Undo would revert, e.g. "Typing", for the Edit menu.
    public var undoActionName: String? { undoStack.last?.actionName }
    public var redoActionName: String? { redoStack.last?.actionName }

    /// Restores the project to before the last edit. The audience output never changes: the live slide is a
    /// snapshot, and only editing commands are recorded.
    public func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(UndoEntry(project: project, actionName: entry.actionName))
        restore(entry.project)
        Log.coordinator.info("Undo \(entry.actionName, privacy: .public)")
    }

    public func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(UndoEntry(project: project, actionName: entry.actionName))
        restore(entry.project)
        Log.coordinator.info("Redo \(entry.actionName, privacy: .public)")
    }

    func restore(_ snapshot: ProjectDocument) {
        // The media library only grows, and imports aren't recorded: an asset added after the snapshot was taken
        // stays, so undoing an earlier edit never loses an import (its file is already in the media folder).
        var snapshot = snapshot
        let snapshotAssetIDs = Set(snapshot.mediaAssets.map(\.id))
        snapshot.mediaAssets += project.mediaAssets.filter { !snapshotAssetIDs.contains($0.id) }
        project = snapshot
        coalescingKey = nil
        // Keep selection and cue pointing at things that still exist; live state is left alone.
        if let selected = state.selectedItemID, project.playlist.item(withID: selected) == nil {
            state.selectedItemID = project.playlist.items.first?.id
        }
        if let preview = state.preview, project.slide(at: preview) == nil {
            state.preview = nil
        }
        lastRejection = nil
    }

    /// Runs an editing command and, if it changed the project, records the previous project for Undo.
    func recordingUndo<Result>(_ actionName: String, coalescing key: String? = nil, _ body: () -> Result) -> Result {
        // Commands that call other commands record once, for the outermost one.
        guard recordingDepth == 0 else { return body() }
        recordingDepth += 1
        defer { recordingDepth -= 1 }
        let before = project
        let result = body()
        guard project != before else { return result }
        let time = now()
        redoStack.removeAll()
        if let key, key == coalescingKey, time.timeIntervalSince(lastEditTime) < Self.coalescingInterval, !undoStack.isEmpty {
            lastEditTime = time
            return result
        }
        undoStack.append(UndoEntry(project: before, actionName: actionName))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        coalescingKey = key
        lastEditTime = time
        return result
    }

    // MARK: - Project commands

    /// Swaps in a different project, e.g. one opened from disk. The audience output is left alone:
    /// the live snapshot, cleared slide and blackout carry over until the operator takes something live.
    /// Selection and cue move to the new project's first item.
    public func replaceProject(_ newProject: ProjectDocument) {
        project = newProject
        // Undo can't reach back into a different project.
        undoStack.removeAll()
        redoStack.removeAll()
        coalescingKey = nil
        state.selectedItemID = newProject.playlist.items.first?.id
        state.preview = nil
        lastRejection = nil
        Log.coordinator.info("Opened project \(newProject.id, privacy: .public)")
    }
}
