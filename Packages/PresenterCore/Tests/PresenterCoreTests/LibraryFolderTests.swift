import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class LibraryFolderTests: XCTestCase {
    private func makeCoordinator() -> (PresentationCoordinator, PresentationDocument, PresentationDocument) {
        let a = PresentationDocument(title: "A", slides: [.text("a")])
        let b = PresentationDocument(title: "B", slides: [.text("b")])
        let item = PresentationItem(presentationID: a.id)
        let project = ProjectDocument(name: "Test", presentations: [a, b],
                                      playlist: PlaylistDocument(title: "Service", items: [item]))
        return (PresentationCoordinator(project: project), a, b)
    }

    func testAddFolderTrimsAndNamesEmptyOnes() {
        let (c, _, _) = makeCoordinator()
        let songs = c.addFolder(named: "  Songs ")
        let untitled = c.addFolder(named: " ")
        XCTAssertEqual(c.project.libraryFolders.map(\.name), ["Songs", "New Folder"])
        XCTAssertEqual(c.project.libraryFolders.map(\.id), [songs.id, untitled.id])
    }

    func testRenameFolderIgnoresEmptyAndRejectsUnknown() {
        let (c, _, _) = makeCoordinator()
        let folder = c.addFolder(named: "Songs")
        XCTAssertEqual(c.renameFolder(folder.id, to: " Hymns "), .applied)
        XCTAssertEqual(c.renameFolder(folder.id, to: ""), .applied)
        XCTAssertEqual(c.project.folder(withID: folder.id)?.name, "Hymns")
        XCTAssertEqual(c.renameFolder(UUID(), to: "X"), .rejected(.unknownFolder))
    }

    func testMovePresentationsIntoAFolderAndBack() {
        let (c, a, b) = makeCoordinator()
        let folder = c.addFolder(named: "Songs")
        let modified = c.project.presentation(withID: a.id)?.updatedAt
        XCTAssertEqual(c.movePresentations([a.id, b.id], toFolder: folder.id), .applied)
        XCTAssertEqual(c.project.presentations.map(\.folderID), [folder.id, folder.id])
        XCTAssertEqual(c.project.presentation(withID: a.id)?.updatedAt, modified, "Moving isn't editing")
        XCTAssertEqual(c.movePresentations([a.id], toFolder: nil), .applied)
        XCTAssertEqual(c.project.presentations.map(\.folderID), [nil, folder.id])
    }

    func testMoveRejectsUnknownFoldersAndPresentations() {
        let (c, a, _) = makeCoordinator()
        XCTAssertEqual(c.movePresentations([a.id], toFolder: UUID()), .rejected(.unknownFolder))
        XCTAssertEqual(c.movePresentations([UUID()], toFolder: nil), .rejected(.unknownPresentation))
        XCTAssertFalse(c.canUndo)
    }

    func testDeleteFolderMovesItsPresentationsToTheTopAndUndoes() {
        let (c, a, b) = makeCoordinator()
        let songs = c.addFolder(named: "Songs")
        let other = c.addFolder(named: "Other")
        c.movePresentations([a.id], toFolder: songs.id)
        c.movePresentations([b.id], toFolder: other.id)

        XCTAssertEqual(c.deleteFolder(songs.id), .applied)
        XCTAssertEqual(c.project.libraryFolders.map(\.id), [other.id])
        XCTAssertEqual(c.project.presentations.map(\.id), [a.id, b.id], "Nothing is deleted")
        XCTAssertEqual(c.project.presentations.map(\.folderID), [nil, other.id])
        XCTAssertEqual(c.project.playlist.items.count, 1, "The show is untouched")

        c.undo()
        XCTAssertEqual(c.project.libraryFolders.map(\.id), [songs.id, other.id])
        XCTAssertEqual(c.project.presentations.map(\.folderID), [songs.id, other.id])
        XCTAssertEqual(c.deleteFolder(UUID()), .rejected(.unknownFolder))
    }

    func testFoldersRoundTripAndOlderFilesHaveNone() throws {
        let (c, a, _) = makeCoordinator()
        let folder = c.addFolder(named: "Songs")
        c.movePresentations([a.id], toFolder: folder.id)
        let data = try JSONEncoder().encode(c.project)
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: data), c.project)

        // A format 4 file: no libraryFolders, and presentations without folderID.
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old["schemaVersion"] = 4
        old["libraryFolders"] = nil
        old["presentations"] = (old["presentations"] as? [[String: Any]])?.map { presentation in
            var presentation = presentation
            presentation["folderID"] = nil
            return presentation
        }
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.libraryFolders.isEmpty)
        XCTAssertEqual(decoded.presentations.map(\.folderID), [nil, nil])
    }
}
