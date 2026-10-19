import Foundation

// Library folders, one level deep. Undoable edits; none of them changes a show or what's live.
extension PresentationCoordinator {
    /// Adds a folder to the library and returns it. Empty text names it "New Folder".
    @discardableResult
    public func addFolder(named name: String) -> LibraryFolder {
        recordingUndo("New Folder") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let folder = LibraryFolder(name: trimmed.isEmpty ? "New Folder" : trimmed)
            project.libraryFolders.append(folder)
            lastRejection = nil
            return folder
        }
    }

    /// Renames a folder. Empty text keeps the current name.
    @discardableResult
    public func renameFolder(_ folderID: UUID, to name: String) -> CommandResult {
        recordingUndo("Rename Folder", coalescing: "rename-folder-\(folderID)") {
            guard let index = project.libraryFolders.firstIndex(where: { $0.id == folderID }) else {
                return reject(.unknownFolder)
            }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { project.libraryFolders[index].name = trimmed }
            return applied()
        }
    }

    /// Deletes a folder. Its presentations aren't deleted: they move to the top of the library.
    @discardableResult
    public func deleteFolder(_ folderID: UUID) -> CommandResult {
        recordingUndo("Delete Folder") {
            guard project.folder(withID: folderID) != nil else { return reject(.unknownFolder) }
            for index in project.presentations.indices where project.presentations[index].folderID == folderID {
                project.presentations[index].folderID = nil
            }
            project.libraryFolders.removeAll { $0.id == folderID }
            return applied()
        }
    }

    /// Moves library presentations into a folder, or to the top of the library when `folderID` is nil.
    @discardableResult
    public func movePresentations(_ presentationIDs: [UUID], toFolder folderID: UUID?) -> CommandResult {
        recordingUndo("Move to Folder") {
            if let folderID, project.folder(withID: folderID) == nil { return reject(.unknownFolder) }
            let ids = Set(presentationIDs)
            guard project.presentations.contains(where: { ids.contains($0.id) }) else { return reject(.unknownPresentation) }
            // Not an edit of the presentation, so its modified date stays.
            for index in project.presentations.indices where ids.contains(project.presentations[index].id) {
                project.presentations[index].folderID = folderID
            }
            return applied()
        }
    }
}
