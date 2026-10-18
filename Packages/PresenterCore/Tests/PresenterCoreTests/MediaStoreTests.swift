import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PresenterCore

final class MediaStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes a solid PNG of the given size and returns its URL.
    private func makePNG(width: Int, height: Int, name: String = "picture.png") throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = root.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testImportCopiesImageAndRecordsSize() throws {
        let source = try makePNG(width: 64, height: 36)
        let store = MediaStore(directory: root.appendingPathComponent("Media"))

        let asset = try store.importImage(at: source)

        XCTAssertEqual(asset.kind, .image)
        XCTAssertEqual(asset.originalFilename, "picture.png")
        XCTAssertEqual(asset.pixelWidth, 64)
        XCTAssertEqual(asset.pixelHeight, 36)
        XCTAssertTrue(asset.storedFilename.hasSuffix(".png"))
        XCTAssertTrue(store.fileExists(for: asset))

        // The copy is independent of the original.
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(store.fileExists(for: asset))
    }

    func testImportRejectsNonImageFile() throws {
        let text = root.appendingPathComponent("notes.png")
        try Data("not an image".utf8).write(to: text)
        let store = MediaStore(directory: root.appendingPathComponent("Media"))

        XCTAssertThrowsError(try store.importImage(at: text)) { error in
            XCTAssertEqual(error as? MediaImportError, .unreadableImage)
        }
    }

    func testDeletedCopyIsReportedMissing() throws {
        let store = MediaStore(directory: root.appendingPathComponent("Media"))
        let asset = try store.importImage(at: try makePNG(width: 8, height: 8))

        try FileManager.default.removeItem(at: store.url(for: asset))

        XCTAssertFalse(store.fileExists(for: asset))
    }

    func testRemoveFilesDeletesOnlyUnkeptCandidates() throws {
        let store = MediaStore(directory: root)
        for name in ["kept.png", "deleted.png", "new.png"] {
            try Data([1]).write(to: root.appendingPathComponent(name))
        }

        let removed = store.removeFiles(among: ["kept.png", "deleted.png"], keeping: ["kept.png"])

        XCTAssertEqual(removed, ["deleted.png"])
        XCTAssertEqual(store.filenames().sorted(), ["kept.png", "new.png"], "Files that weren't candidates stay")
    }
}
