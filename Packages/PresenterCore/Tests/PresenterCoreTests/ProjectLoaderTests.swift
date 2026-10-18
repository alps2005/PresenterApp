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
    private let starter = ProjectDocument(name: "Starter")

    private func load() -> ProjectLoader.Outcome {
        ProjectLoader.loadInitialProject(from: store, backups: backups, now: launch, starter: { self.starter })
    }

    func testNothingSavedStartsWithTheStarterAndWritesNothing() throws {
        let outcome = load()
        XCTAssertEqual(outcome.project, starter)
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

    func testUnreadableFileIsMovedAsideAndTheStarterOpens() throws {
        try Data("{ not json".utf8).write(to: store.fileURL)

        let outcome = load()

        XCTAssertEqual(outcome.project, starter)
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

        XCTAssertEqual(outcome.project, starter)
        XCTAssertTrue(outcome.problem?.contains("newer version") ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testStarterHasThemesAndNothingElse() {
        let project = ProjectDocument.starter()
        XCTAssertEqual(project.themes.map(\.name), Theme.presets().map(\.name))
        XCTAssertTrue(project.presentations.isEmpty)
        XCTAssertTrue(project.playlist.items.isEmpty)
        XCTAssertTrue(project.mediaAssets.isEmpty)
        XCTAssertTrue(project.timers.isEmpty)
        XCTAssertTrue(project.messages.isEmpty)
        XCTAssertTrue(project.props.slides.isEmpty)
        XCTAssertNil(project.defaultThemeID)
    }
}
