import Foundation

// Shows: playlists of library presentations, one of them open. Opening a show is like opening a project: the
// audience output is left alone, and undo starts afresh, so it can't reach into a show that isn't on screen.
extension PresentationCoordinator {
    /// Opens a show: the operator's view and the playlist commands switch to it. What's live stays on the audience
    /// output until something else is taken live, and Next and Previous wait for that.
    @discardableResult
    public func openPlaylist(_ playlistID: UUID) -> CommandResult {
        guard let index = project.playlists.firstIndex(where: { $0.id == playlistID }) else { return reject(.unknownShow) }
        project.playlists[index].lastOpenedAt = now()
        guard project.activePlaylistID != playlistID else { return applied() }
        project.activePlaylistID = playlistID
        undoStack.removeAll()
        redoStack.removeAll()
        coalescingKey = nil
        state.selectedItemID = project.playlist.items.first?.id
        state.preview = nil
        Log.coordinator.info("Opened show \(playlistID, privacy: .public)")
        return applied()
    }

    /// Makes an empty show and opens it. Empty text names it "Untitled Show".
    @discardableResult
    public func addPlaylist(title: String) -> PlaylistDocument {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let playlist = PlaylistDocument(title: trimmed.isEmpty ? "Untitled Show" : trimmed)
        project.playlists.append(playlist)
        openPlaylist(playlist.id)
        return playlist
    }

    /// Copies a show, with the same presentations (not copies of them), and returns the copy. The open show
    /// stays open.
    @discardableResult
    public func duplicatePlaylist(_ playlistID: UUID) -> PlaylistDocument? {
        guard let source = project.playlist(withID: playlistID) else {
            _ = reject(.unknownShow)
            return nil
        }
        return recordingUndo("Duplicate Show") {
            // New item IDs: an item belongs to one show, so a live slide or cue never points into two.
            let copy = PlaylistDocument(title: "\(source.title) Copy",
                                        items: source.items.map { PresentationItem(presentationID: $0.presentationID) })
            let index = project.playlists.firstIndex { $0.id == playlistID } ?? project.playlists.endIndex - 1
            project.playlists.insert(copy, at: index + 1)
            lastRejection = nil
            return copy
        }
    }

    /// Deletes a show. Its presentations stay in the library. Deleting the open show opens the one opened most
    /// recently, which starts undo afresh; deleting another can be undone. The last show can't be deleted.
    @discardableResult
    public func deletePlaylist(_ playlistID: UUID) -> CommandResult {
        guard project.playlist(withID: playlistID) != nil else { return reject(.unknownShow) }
        guard project.playlists.count > 1 else { return reject(.lastShow) }
        guard playlistID == project.activePlaylistID else {
            return recordingUndo("Delete Show") {
                project.playlists.removeAll { $0.id == playlistID }
                return applied()
            }
        }
        let next = project.playlists
            .filter { $0.id != playlistID }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
        guard let next else { return reject(.lastShow) }
        openPlaylist(next.id)
        project.playlists.removeAll { $0.id == playlistID }
        Log.coordinator.info("Deleted show \(playlistID, privacy: .public)")
        return applied()
    }

    /// Dates the open show when a project is loaded, at launch or from a file, as opening a show does. Without
    /// it, the show open at launch looks never opened, and deleting another open show could skip it.
    func markOpenShowOpened() {
        guard let index = project.playlists.firstIndex(where: { $0.id == project.activePlaylistID }) else { return }
        project.playlists[index].lastOpenedAt = now()
    }
}
