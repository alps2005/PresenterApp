import Foundation
import XCTest
@testable import PresenterCore

final class BackupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectURL: URL { root.appendingPathComponent("Project.json") }

    private func backupNames(_ backups: ProjectBackups) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: backups.directory.path).sorted()
    }

    // MARK: - Names and the prune rule

    func testFilenameRoundTripsItsDate() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertEqual(ProjectBackups.filename(at: date), "Project-1760000000.json")
        XCTAssertEqual(ProjectBackups.date(fromFilename: "Project-1760000000.json"), date)
    }

    func testOtherFilesAreNotBackups() {
        for name in ["Project.json", "Project-abc.json", "Project-12.txt", "Notes-12.json", ".DS_Store"] {
            XCTAssertNil(ProjectBackups.date(fromFilename: name), name)
        }
    }

    func testPruneKeepsTheNewestByDateNotByName() {
        // 9 sorts after 10 as text; the rule must compare dates.
        let names = ["Project-9.json", "Project-10.json", "Project-11.json", "Project-200.json"]
        XCTAssertEqual(
            Set(ProjectBackups.filenamesToPrune(names, keeping: 2)),
            ["Project-9.json", "Project-10.json"]
        )
    }

    func testPruneNeverListsOtherFiles() {
        let names = ["Project-1.json", "Project-2.json", "Readme.txt", "Project.json"]
        XCTAssertEqual(ProjectBackups.filenamesToPrune(names, keeping: 0).sorted(), ["Project-1.json", "Project-2.json"])
        XCTAssertEqual(ProjectBackups.filenamesToPrune(names, keeping: 10), [])
    }

    // MARK: - On disk

    func testSaveKeepsOnlyTheNewestBackups() throws {
        let backups = ProjectBackups(projectFileURL: projectURL, limit: 3)
        for second in 1...5 {
            try backups.save(.sample(), now: Date(timeIntervalSince1970: TimeInterval(second)))
        }
        XCTAssertEqual(try backupNames(backups), ["Project-3.json", "Project-4.json", "Project-5.json"])
    }

    func testBackUpFileCopiesTheProjectAndSkipsAnUnchangedOne() throws {
        let store = ProjectStore(fileURL: projectURL)
        var project = ProjectDocument.sample()
        try store.save(project)
        let backups = ProjectBackups(projectFileURL: projectURL)

        let first = try XCTUnwrap(try backups.backUpFile(at: projectURL, now: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(try ProjectStore(fileURL: first).load(), project)

        // Relaunching without changes doesn't push older backups out with identical copies.
        XCTAssertNil(try backups.backUpFile(at: projectURL, now: Date(timeIntervalSince1970: 2)))

        project.name = "Changed"
        try store.save(project)
        XCTAssertNotNil(try backups.backUpFile(at: projectURL, now: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(try backupNames(backups), ["Project-1.json", "Project-3.json"])
    }

    func testBackUpFileDoesNothingWithoutAProject() throws {
        let backups = ProjectBackups(projectFileURL: projectURL)
        XCTAssertNil(try backups.backUpFile(at: projectURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.directory.path))
    }

    func testBackUpFilePrunes() throws {
        try ProjectStore(fileURL: projectURL).save(.sample())
        let backups = ProjectBackups(projectFileURL: projectURL, limit: 2)
        for second in 1...3 {
            var project = ProjectDocument.sample()
            project.name = "Version \(second)"
            try ProjectStore(fileURL: projectURL).save(project)
            try backups.backUpFile(at: projectURL, now: Date(timeIntervalSince1970: TimeInterval(second)))
        }
        XCTAssertEqual(try backupNames(backups), ["Project-2.json", "Project-3.json"])
    }
}
