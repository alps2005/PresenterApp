import Foundation
import XCTest
@testable import PresenterCore

final class ProjectLoaderTests: XCTestCase {
    private var root: URL!
    private let launch = Date(timeIntervalSince1970: 1_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var store: ProjectStore { ProjectStore(fileURL: root.appendingPathComponent("Project.json")) }
    private var backups: ProjectBackups { ProjectBackups(projectFileURL: store.fileURL) }
    private let sample = ProjectDocument(name: "Sample")

    private func load() -> ProjectLoader.Outcome {
        ProjectLoader.loadInitialProject(from: store, backups: backups, now: launch, sample: { self.sample })
    }

    func testNothingSavedStartsWithTheSampleAndWritesNothing() throws {
        let outcome = load()
        XCTAssertEqual(outcome.project, sample)
        XCTAssertNil(outcome.problem)
        XCTAssertFalse(outcome.loadedFromDisk)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testSavedProjectLoadsAndIsBackedUp() throws {
        let saved = ProjectDocument(name: "Sunday")
        try store.save(saved)

        let outcome = load()

        XCTAssertEqual(outcome.project, saved)
        XCTAssertTrue(outcome.loadedFromDisk)
        XCTAssertNil(outcome.backupError)
        let backup = backups.directory.appendingPathComponent(ProjectBackups.filename(at: launch))
        XCTAssertEqual(try ProjectStore(fileURL: backup).load(), saved)
    }

    func testUnreadableFileIsMovedAsideAndTheSampleOpens() throws {
        try Data("{ not json".utf8).write(to: store.fileURL)

        let outcome = load()

        XCTAssertEqual(outcome.project, sample)
        XCTAssertFalse(outcome.loadedFromDisk)
        let problem = try XCTUnwrap(outcome.problem)
        XCTAssertTrue(problem.contains("moved to"), problem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Project.unreadable-1000.json").path))
    }

    func testNewerFileIsMovedAsideNotOverwritten() throws {
        var newer = ProjectDocument(name: "From the future")
        newer.schemaVersion = ProjectDocument.currentSchemaVersion + 1
        try Data(ProjectStore.encode(newer)).write(to: store.fileURL)

        let outcome = load()

        XCTAssertEqual(outcome.project, sample)
        XCTAssertTrue(outcome.problem?.contains("newer version") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
