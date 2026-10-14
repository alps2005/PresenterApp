import Foundation
import XCTest
@testable import PresenterCore

final class ProjectArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func project(with assets: [MediaAsset]) -> ProjectDocument {
        ProjectDocument(name: "P", presentations: [PresentationDocument(title: "P", slides: [.text("x")])], mediaAssets: assets)
    }

    func testExportedImagesArriveInTheOtherMacsMediaFolder() throws {
        let here = root.appendingPathComponent("HereMedia")
        let there = root.appendingPathComponent("ThereMedia")
        try FileManager.default.createDirectory(at: here, withIntermediateDirectories: true)
        let asset = MediaAsset(originalFilename: "sky.png", storedFilename: "A.png", pixelWidth: 1, pixelHeight: 1)
        try Data([1, 2, 3]).write(to: here.appendingPathComponent("A.png"))
        let original = project(with: [asset])

        let data = try ProjectArchive.export(original, mediaDirectory: here)
        let opened = try ProjectArchive.open(data, mediaDirectory: there)

        XCTAssertEqual(opened, original)
        XCTAssertEqual(try Data(contentsOf: there.appendingPathComponent("A.png")), Data([1, 2, 3]))
    }

    func testMissingMediaIsLeftOutAndExistingFilesAreKept() throws {
        let media = root.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let present = MediaAsset(originalFilename: "a.png", storedFilename: "A.png", pixelWidth: 1, pixelHeight: 1)
        let missing = MediaAsset(originalFilename: "b.png", storedFilename: "B.png", pixelWidth: 1, pixelHeight: 1)
        try Data([9]).write(to: media.appendingPathComponent("A.png"))
        let data = try ProjectArchive.export(project(with: [present, missing]), mediaDirectory: media)

        // Opening on a Mac that already has A.png keeps its copy.
        let target = root.appendingPathComponent("Target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([7]).write(to: target.appendingPathComponent("A.png"))
        _ = try ProjectArchive.open(data, mediaDirectory: target)

        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("A.png")), Data([7]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("B.png").path))
    }

    func testFilesTheProjectDoesNotReferenceAreNeverWritten() throws {
        let asset = MediaAsset(originalFilename: "a.png", storedFilename: "A.png", pixelWidth: 1, pixelHeight: 1)
        let projectData = try JSONEncoder().encode(project(with: [asset]))
        let projectJSON = String(decoding: projectData, as: UTF8.self)
        let payload = Data([1]).base64EncodedString()
        let crafted = """
        {"presenterArchive":1,"project":\(projectJSON),"media":{"../escape.png":"\(payload)","other.png":"\(payload)"}}
        """
        let media = root.appendingPathComponent("Media")

        _ = try ProjectArchive.open(Data(crafted.utf8), mediaDirectory: media)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.appendingPathComponent("other.png").path))
    }

    func testPlainProjectFilesStillOpen() throws {
        let original = project(with: [])
        let opened = try ProjectArchive.open(try ProjectStore.encode(original), mediaDirectory: root)
        XCTAssertEqual(opened, original)
    }

    func testArchiveFromANewerVersionIsRejected() throws {
        var newer = project(with: [])
        newer.schemaVersion = ProjectDocument.currentSchemaVersion + 1
        let data = try ProjectArchive.export(newer, mediaDirectory: root)

        XCTAssertThrowsError(try ProjectArchive.open(data, mediaDirectory: root)) { error in
            guard case ProjectStoreError.newerSchema = error else { return XCTFail("Got \(error)") }
        }
    }
}
