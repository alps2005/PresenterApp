import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#endif
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

#if canImport(ImageIO)
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

#endif

    func testRemoveFilesDeletesOnlyUnkeptCandidates() throws {
        let store = MediaStore(directory: root, probe: FakeMediaProbe())
        for name in ["kept.png", "deleted.png", "new.png"] {
            try Data([1]).write(to: root.appendingPathComponent(name))
        }

        let removed = store.removeFiles(among: ["kept.png", "deleted.png"], keeping: ["kept.png"])

        XCTAssertEqual(removed, ["deleted.png"])
        XCTAssertEqual(store.filenames().sorted(), ["kept.png", "new.png"], "Files that weren't candidates stay")
    }

    func testImportsCopyUnderTheAssetIDAndKeepWhatTheProbeSays() async throws {
        let store = MediaStore(directory: root.appendingPathComponent("Media"), probe: FakeMediaProbe())
        for name in ["Logo.PNG", "loop.mp4", "song.wav", "noext"] {
            try Data([1, 2, 3]).write(to: root.appendingPathComponent(name))
        }

        let image = try store.importImage(at: root.appendingPathComponent("Logo.PNG"))
        XCTAssertEqual(image.kind, .image)
        XCTAssertEqual(image.originalFilename, "Logo.PNG")
        XCTAssertEqual(image.storedFilename, "\(image.id.uuidString).png", "Named by the asset's ID, extension lowercased")
        XCTAssertEqual([image.pixelWidth, image.pixelHeight], [64, 36])
        XCTAssertTrue(store.fileExists(for: image))

        let video = try await store.importVideo(at: root.appendingPathComponent("loop.mp4"))
        XCTAssertEqual(video.kind, .video)
        XCTAssertEqual([video.pixelWidth, video.pixelHeight], [1920, 1080])
        XCTAssertEqual(video.duration, 12)

        let audio = try await store.importAudio(at: root.appendingPathComponent("song.wav"))
        XCTAssertEqual(audio.kind, .audio)
        XCTAssertEqual([audio.pixelWidth, audio.pixelHeight], [0, 0])
        XCTAssertEqual(audio.duration, 180)

        let bare = try store.importImage(at: root.appendingPathComponent("noext"))
        XCTAssertEqual(bare.storedFilename, "\(bare.id.uuidString).img", "No extension gets the kind's default")
        XCTAssertEqual(Set(store.filenames()), Set([image, video, audio, bare].map(\.storedFilename)))
    }

    func testWhatTheProbeRejectsIsntCopied() async throws {
        let store = MediaStore(directory: root.appendingPathComponent("Media"), probe: FakeMediaProbe(acceptsNothing: true))
        let file = root.appendingPathComponent("file.bin")
        try Data([1]).write(to: file)

        XCTAssertThrowsError(try store.importImage(at: file)) { XCTAssertEqual($0 as? MediaImportError, .unreadableImage) }
        do {
            _ = try await store.importVideo(at: file)
            XCTFail("Rejected video")
        } catch {
            XCTAssertEqual(error as? MediaImportError, .unplayableVideo)
        }
        do {
            _ = try await store.importAudio(at: file)
            XCTFail("Rejected audio")
        } catch {
            XCTAssertEqual(error as? MediaImportError, .unplayableAudio)
        }
        XCTAssertEqual(store.filenames(), [], "Nothing copied")
    }
}

/// Answers like a platform's media checks without reading the file, so the store's own logic is tested everywhere.
struct FakeMediaProbe: MediaProbe {
    var acceptsNothing = false

    func imageSize(at url: URL) -> (width: Int, height: Int)? {
        acceptsNothing ? nil : (64, 36)
    }

    func video(at url: URL) async -> (width: Int, height: Int, duration: Double)? {
        acceptsNothing ? nil : (1920, 1080, 12)
    }

    func audioDuration(at url: URL) async -> Double? {
        acceptsNothing ? nil : 180
    }
}
