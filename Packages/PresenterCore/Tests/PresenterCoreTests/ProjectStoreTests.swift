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
}
