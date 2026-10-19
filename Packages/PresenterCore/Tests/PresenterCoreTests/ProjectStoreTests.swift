import Foundation
import XCTest
@testable import PresenterCore

final class ProjectStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var fileURL: URL { root.appendingPathComponent("Nested/Project.json") }

    func testLoadReturnsNilWhenNothingSaved() throws {
        XCTAssertNil(try ProjectStore(fileURL: fileURL).load())
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ProjectStore(fileURL: fileURL)
        let project = ProjectDocument.sample()

        try store.save(project)

        XCTAssertEqual(try store.load(), project)
    }

    func testSaveOverwritesPreviousVersion() throws {
        let store = ProjectStore(fileURL: fileURL)
        var project = ProjectDocument.sample()
        try store.save(project)

        project.name = "Renamed"
        try store.save(project)

        XCTAssertEqual(try store.load()?.name, "Renamed")
    }

    func testCorruptFileIsReportedAsUnreadable() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: fileURL)

        XCTAssertThrowsError(try ProjectStore(fileURL: fileURL).load()) { error in
            guard case ProjectStoreError.unreadable = error else { return XCTFail("Got \(error)") }
        }
    }

    func testFileMissingRequiredFieldsIsReportedAsUnreadable() throws {
        let json = #"{ "schemaVersion": 1, "name": "No ID" }"#
        XCTAssertThrowsError(try ProjectStore.decode(Data(json.utf8))) { error in
            guard case ProjectStoreError.unreadable = error else { return XCTFail("Got \(error)") }
        }
    }

    func testNewerSchemaIsRejectedRatherThanPartiallyLoaded() throws {
        var project = ProjectDocument.sample()
        project.schemaVersion = ProjectDocument.currentSchemaVersion + 1
        let data = try JSONEncoder().encode(project)

        XCTAssertThrowsError(try ProjectStore.decode(data)) { error in
            XCTAssertEqual(error as? ProjectStoreError, .newerSchema(
                found: ProjectDocument.currentSchemaVersion + 1,
                supported: ProjectDocument.currentSchemaVersion
            ))
        }
    }

    func testQuarantineMovesFileAsideSoItIsNotOverwritten() throws {
        let store = ProjectStore(fileURL: fileURL)
        try store.save(.sample())

        let moved = try store.quarantine(now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(moved.lastPathComponent, "Project.unreadable-1000.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertNil(try store.load())
    }

    func testSavedProjectsUseTheCurrentSchemaVersion() throws {
        XCTAssertEqual(ProjectDocument.currentSchemaVersion, 5)
        let data = try ProjectStore.encode(.sample())
        struct Probe: Decodable { let schemaVersion: Int }
        XCTAssertEqual(try JSONDecoder().decode(Probe.self, from: data).schemaVersion, 5)
    }

    /// A version 1 file (beta 1) loads, gets today's defaults, and is saved back as the current version.
    func testVersionOneFileLoadsAndSavesAsCurrent() throws {
        let json = """
        {
          "id": "8E4B1C2A-0000-4000-8000-000000000001",
          "name": "Beta 1",
          "schemaVersion": 1,
          "presentations": [],
          "playlist": {"id": "8E4B1C2A-0000-4000-8000-000000000005", "title": "S", "items": []},
          "mediaAssets": []
        }
        """
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: fileURL)
        let store = ProjectStore(fileURL: fileURL)

        let project = try XCTUnwrap(try store.load())
        XCTAssertEqual(project.name, "Beta 1")
        XCTAssertEqual(project.schemaVersion, ProjectDocument.currentSchemaVersion)
        XCTAssertEqual(project.timers.map(\.name), TimerDefinition.defaults().map(\.name))

        try store.save(project)
        XCTAssertEqual(try store.load()?.schemaVersion, ProjectDocument.currentSchemaVersion)
    }
}
