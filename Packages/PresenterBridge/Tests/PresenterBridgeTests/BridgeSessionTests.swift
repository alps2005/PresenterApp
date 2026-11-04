import Foundation
import PresenterCore
import XCTest
@testable import PresenterBridge

@MainActor
final class BridgeSessionTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private static let lyrics = """
    Verse 1
    First line
    Second line

    Chorus
    Sing it loud
    """

    // MARK: - Helpers

    private func reply(_ session: BridgeSession, _ command: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: command)
        let answer = session.send(String(decoding: data, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])
    }

    @discardableResult
    private func ok(_ session: BridgeSession, _ command: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let answer = try reply(session, command)
        XCTAssertEqual(answer["ok"] as? Bool, true, "\(command["type"] ?? "?"): \(answer["error"] ?? "")", file: file, line: line)
        return answer
    }

    private func state(_ session: BridgeSession) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.stateJSON().utf8)) as? [String: Any])
    }

    private func slides(_ state: [String: Any]) -> [[String: Any]] {
        state["slides"] as? [[String: Any]] ?? []
    }

    private func position(_ slide: [String: Any]) -> [String: Any] {
        slide["position"] as? [String: Any] ?? [:]
    }

    private func texts(_ slide: [String: Any]?) -> [String] {
        let elements = (slide?["elements"] as? [[String: Any]]) ?? []
        return elements.compactMap { $0["text"] as? String }
    }

    private func takeLive(_ session: BridgeSession, _ slide: [String: Any]) throws {
        var command = position(slide)
        command["type"] = "takeLive"
        try ok(session, command)
    }

    private var projectFile: URL { folder.appendingPathComponent("Project.json") }

    // MARK: - Tests

    func testANewFolderStartsAnEmptyProjectAndWritesNothingUntilItChanges() throws {
        let session = BridgeSession(dataDirectory: folder)
        let state = try state(session)
        XCTAssertEqual(state["projectName"] as? String, "My Show")
        XCTAssertEqual((state["items"] as? [Any])?.count, 0)
        XCTAssertEqual((state["shows"] as? [Any])?.count, 1)
        XCTAssertNil(state["problem"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectFile.path))
    }

    func testASongTypedInIsSavedAndOpensAgain() throws {
        let session = BridgeSession(dataDirectory: folder)
        try ok(session, ["type": "addSong", "title": "Amazing", "text": Self.lyrics])
        let state = try state(session)
        XCTAssertEqual((state["items"] as? [[String: Any]])?.first?["title"] as? String, "Amazing")
        XCTAssertEqual(slides(state).map { $0["label"] as? String }, ["Verse 1", "Chorus"])
        XCTAssertEqual(slides(state).map { $0["section"] as? String }, ["verse", "chorus"])
        XCTAssertEqual(texts(slides(state).first?["slide"] as? [String: Any]), ["First line\nSecond line"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectFile.path))

        let reopened = BridgeSession(dataDirectory: folder)
        XCTAssertEqual(reopened.coordinator.project.presentations.map(\.title), ["Amazing"])
    }

    func testLiveControlsMoveThroughTheShowAndSayWhyWhenTheyCant() throws {
        let session = BridgeSession(dataDirectory: folder)
        try ok(session, ["type": "addSong", "title": "One", "text": Self.lyrics])
        let first = slides(try state(session))
        try takeLive(session, first[0])

        var now = try state(session)
        XCTAssertEqual((now["live"] as? [String: Any])?["slideID"] as? String, position(first[0])["slideID"] as? String)
        XCTAssertEqual(texts(now["audience"] as? [String: Any]), ["First line\nSecond line"])

        try ok(session, ["type": "next"])
        now = try state(session)
        XCTAssertEqual(texts(now["audience"] as? [String: Any]), ["Sing it loud"])

        let atEnd = try reply(session, ["type": "next"])
        XCTAssertEqual(atEnd["ok"] as? Bool, false)
        XCTAssertEqual(atEnd["error"] as? String, CommandRejection.atEndOfPlaylist.message)

        try ok(session, ["type": "previous"])
        try ok(session, ["type": "blackout"])
        now = try state(session)
        XCTAssertNil(now["audience"])
        XCTAssertEqual(now["isBlackout"] as? Bool, true)
        XCTAssertEqual(now["canRestore"] as? Bool, true)

        try ok(session, ["type": "restore"])
        try ok(session, ["type": "clearSlide"])
        now = try state(session)
        XCTAssertEqual(texts(now["audience"] as? [String: Any]), [])
        XCTAssertNil(now["live"])
    }

    func testASectionKeyTakesThatSectionLive() throws {
        let session = BridgeSession(dataDirectory: folder)
        try ok(session, ["type": "addSong", "title": "One", "text": Self.lyrics])
        try ok(session, ["type": "section", "key": "c"])
        XCTAssertEqual(texts(try state(session)["audience"] as? [String: Any]), ["Sing it loud"])
        XCTAssertEqual(try reply(session, ["type": "section", "key": "b"])["error"] as? String,
                       CommandRejection.noSuchSection.message)
    }

    func testImportingSongFilesAddsTheGoodOnesAndListsTheRest() throws {
        let files = folder.appendingPathComponent("songs", isDirectory: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let chordPro = files.appendingPathComponent("Grace.cho")
        try "{title: Grace}\n{start_of_verse}\n[G]Amazing grace\n{end_of_verse}\n".write(to: chordPro, atomically: true, encoding: .utf8)
        let broken = files.appendingPathComponent("Broken.xml")
        try "<song xmlns=\"http://openlyrics.info/namespace/2009/song\"><properties>".write(to: broken, atomically: true, encoding: .utf8)
        let missing = files.appendingPathComponent("Gone.txt")

        let session = BridgeSession(dataDirectory: folder)
        let answer = try ok(session, ["type": "importSongs", "paths": [chordPro.path, broken.path, missing.path]])
        XCTAssertEqual(answer["added"] as? Int, 1)
        let failures = answer["failures"] as? [[String: String]]
        XCTAssertEqual(failures?.map { $0["file"] }, ["Broken.xml", "Gone.txt"])
        XCTAssertEqual(session.coordinator.project.presentations.map(\.title), ["Grace"])
    }

    func testEditingWordsRewritesTheSlides() throws {
        let session = BridgeSession(dataDirectory: folder)
        try ok(session, ["type": "addSong", "title": "One", "text": Self.lyrics])
        let presentationID = try XCTUnwrap(session.coordinator.project.presentations.first?.id.uuidString)

        let words = try ok(session, ["type": "words", "presentationID": presentationID])
        XCTAssertEqual(words["text"] as? String, "Verse 1\nFirst line\nSecond line\n\nChorus\nSing it loud")

        try ok(session, ["type": "editWords", "presentationID": presentationID, "title": "Two",
                         "text": "Verse 1\nNew words\n\nChorus\nNew chorus\n\nBridge\nNew bridge"])
        let state = try state(session)
        XCTAssertEqual(slides(state).count, 3)
        XCTAssertEqual((state["items"] as? [[String: Any]])?.first?["title"] as? String, "Two")
        XCTAssertEqual(try reply(session, ["type": "editWords", "presentationID": presentationID, "text": "  "])["ok"] as? Bool, false)

        try ok(session, ["type": "undo"])
        XCTAssertEqual(slides(try self.state(session)).count, 2)
    }

    func testMovingAnItemPutsItAtTheIndexGiven() throws {
        let session = BridgeSession(dataDirectory: folder)
        for title in ["A", "B", "C"] { try ok(session, ["type": "addSong", "title": title, "text": "Words"]) }
        func order() throws -> [String] {
            (try state(session)["items"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []
        }
        let items = session.coordinator.project.playlist.items
        try ok(session, ["type": "moveItem", "itemID": items[0].id.uuidString, "index": 2])
        XCTAssertEqual(try order(), ["B", "C", "A"])
        try ok(session, ["type": "moveItem", "itemID": items[0].id.uuidString, "index": 0])
        XCTAssertEqual(try order(), ["A", "B", "C"])
        try ok(session, ["type": "removeItem", "itemID": items[1].id.uuidString])
        XCTAssertEqual(try order(), ["A", "C"])
        // Still in the library, so it can go back in.
        try ok(session, ["type": "addToShow", "presentationID": items[1].presentationID.uuidString])
        XCTAssertEqual(try order(), ["A", "C", "B"])
    }

    func testShowsCanBeAddedOpenedAndDeleted() throws {
        let session = BridgeSession(dataDirectory: folder)
        let added = try ok(session, ["type": "addShow", "title": "Sunday"])
        let showID = try XCTUnwrap(added["showID"] as? String)
        var state = try state(session)
        XCTAssertEqual(state["activeShowID"] as? String, showID)
        XCTAssertEqual((state["shows"] as? [Any])?.count, 2)
        try ok(session, ["type": "deleteShow", "showID": showID])
        state = try self.state(session)
        XCTAssertEqual((state["shows"] as? [Any])?.count, 1)
    }

    func testAnExportedProjectOpensElsewhereAndTheOldOneIsBackedUp() throws {
        let session = BridgeSession(dataDirectory: folder.appendingPathComponent("first"))
        try ok(session, ["type": "addSong", "title": "Moved", "text": Self.lyrics])
        let file = folder.appendingPathComponent("Moved.json")
        try ok(session, ["type": "exportProject", "path": file.path])

        let other = BridgeSession(dataDirectory: folder.appendingPathComponent("second"))
        try ok(other, ["type": "addSong", "title": "Was here", "text": "Words"])
        let opened = try ok(other, ["type": "openProject", "path": file.path])
        XCTAssertEqual(other.coordinator.project.presentations.map(\.title), ["Moved"])
        let backup = try XCTUnwrap(opened["backup"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup))

        let notAProject = try reply(other, ["type": "openProject", "path": folder.appendingPathComponent("nothing.json").path])
        XCTAssertEqual(notAProject["ok"] as? Bool, false)
        XCTAssertEqual(other.coordinator.project.presentations.map(\.title), ["Moved"])
    }

    func testCommandsItCantReadAreTurnedDownWithASentence() throws {
        let session = BridgeSession(dataDirectory: folder)
        for command in ["not json", #"{"type":"fly"}"#, #"{"type":"takeLive"}"#, #"{"type":"selectItem","itemID":"nope"}"#] {
            let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(session.send(command).utf8)) as? [String: Any])
            XCTAssertEqual(answer["ok"] as? Bool, false, command)
            XCTAssertFalse((answer["error"] as? String ?? "").isEmpty, command)
        }
    }

    func testAnUnreadableProjectIsMovedAsideAndSaid() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "not a project".write(to: projectFile, atomically: true, encoding: .utf8)
        let session = BridgeSession(dataDirectory: folder)
        XCTAssertNotNil(try state(session)["problem"])
        try ok(session, ["type": "dismissProblem"])
        XCTAssertNil(try state(session)["problem"])
    }

    func testSlidesComeReadyToDraw() throws {
        var project = ProjectDocument.sample()
        project.name = "Sample"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectStore(fileURL: projectFile).save(project)
        let session = BridgeSession(dataDirectory: folder)
        let state = try state(session)
        let slide = try XCTUnwrap(slides(state).first?["slide"] as? [String: Any])
        let background = try XCTUnwrap(slide["background"] as? [String: Any])
        XCTAssertNotNil(background["kind"] as? String)
        let text = try XCTUnwrap((slide["elements"] as? [[String: Any]])?.first { $0["kind"] as? String == "text" })
        let style = try XCTUnwrap(text["style"] as? [String: Any])
        XCTAssertNotNil(style["fontSize"] as? Double)
        XCTAssertNotNil(style["color"] as? [String: Any])
    }

    // MARK: - The C interface

    func testTheCInterfaceOpensRunsAndCloses() throws {
        let handle = try XCTUnwrap(folder.path.withCString { presenter_open($0) })
        func call(_ result: UnsafeMutablePointer<CChar>?) throws -> [String: Any] {
            let pointer = try XCTUnwrap(result)
            defer { presenter_free(pointer) }
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(String(cString: pointer).utf8)) as? [String: Any])
        }
        let added = try #"{"type":"addSong","title":"Ñandú","text":"Canción"}"#.withCString { try call(presenter_send(handle, $0)) }
        XCTAssertEqual(added["ok"] as? Bool, true)
        let state = try call(presenter_state(handle))
        XCTAssertEqual((state["items"] as? [[String: Any]])?.first?["title"] as? String, "Ñandú")
        XCTAssertEqual(presenter_tick(handle), 0)
        XCTAssertEqual(presenter_schema_version(), Int32(ProjectDocument.currentSchemaVersion))
        presenter_close(handle)
        XCTAssertEqual(BridgeSession(dataDirectory: folder).coordinator.project.presentations.first?.slides.first?.primaryText, "Canción")
    }
}
