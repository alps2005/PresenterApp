import AVFoundation
import Foundation
import XCTest
@testable import PresenterCore

final class VideoTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes a one-second, 64×36 H.264 movie of solid frames.
    private struct MovieWriterStalled: Error {}

    private func makeMovie() async throws -> URL {
        let url = root.appendingPathComponent("clip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 36,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 36,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        // Fail after 10 seconds rather than hang the test run if the writer stalls.
        let deadline = Date.now.addingTimeInterval(10)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData {
                guard Date.now < deadline else { throw MovieWriterStalled() }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let pool = try XCTUnwrap(adaptor.pixelBufferPool, "No pixel buffer pool")
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            XCTAssertTrue(adaptor.append(try XCTUnwrap(buffer), withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testImportVideoCopiesAndDescribesIt() async throws {
        let movie = try await makeMovie()
        let store = MediaStore(directory: root.appendingPathComponent("Media"))

        let asset = try await store.importVideo(at: movie)

        XCTAssertEqual(asset.kind, .video)
        XCTAssertEqual(asset.pixelWidth, 64)
        XCTAssertEqual(asset.pixelHeight, 36)
        XCTAssertEqual(asset.duration ?? 0, 1, accuracy: 0.15)
        XCTAssertTrue(store.fileExists(for: asset))
    }

    func testNonVideoFileIsRejected() async throws {
        let notVideo = root.appendingPathComponent("notes.mov")
        try Data("hello".utf8).write(to: notVideo)
        do {
            _ = try await MediaStore(directory: root).importVideo(at: notVideo)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? MediaImportError, .unplayableVideo)
        }
    }

    func testVideoBackgroundRoundTripsAndOldAssetsLoad() throws {
        let asset = MediaAsset(kind: .video, originalFilename: "loop.mp4", storedFilename: "l.mp4",
                               pixelWidth: 1920, pixelHeight: 1080, duration: 12.5)
        let slide = SlideDocument(elements: [], background: .video(VideoBackground(assetID: asset.id, loops: false, dimming: 0.3)))
        let project = ProjectDocument(name: "P", presentations: [PresentationDocument(title: "P", slides: [slide])], mediaAssets: [asset])
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(project)), project)

        let old = #"{"id":"\#(UUID())","kind":"image","originalFilename":"a.png","storedFilename":"a.png","pixelWidth":1,"pixelHeight":1,"importedAt":0}"#
        XCTAssertNil(try JSONDecoder().decode(MediaAsset.self, from: Data(old.utf8)).duration)
    }

    @MainActor
    func testMediaCueGoesOnTheBackgroundLayerAndTransparentSlidesKeepIt() {
        let video = MediaAsset(kind: .video, originalFilename: "loop.mp4", storedFilename: "l.mp4", pixelWidth: 4, pixelHeight: 3)
        let words = SlideDocument(elements: [.text(TextElement(text: "Hi"))], background: .transparent)
        let presentation = PresentationDocument(title: "P", slides: [words])
        let item = PresentationItem(presentationID: presentation.id)
        let c = PresentationCoordinator(project: ProjectDocument(
            name: "T", presentations: [presentation], playlist: PlaylistDocument(title: "P", items: [item]), mediaAssets: [video]
        ))
        let background = SlideBackground.video(VideoBackground(assetID: video.id))

        XCTAssertEqual(c.showBackground(background), .applied)
        c.takeLive(slideID: words.id, inItem: item.id)

        XCTAssertEqual(c.audienceScene, .slide(RenderedSlide(slide: words, background: background)))
        XCTAssertEqual(c.showBackground(.video(VideoBackground(assetID: UUID()))), .rejected(.unknownMediaAsset))
        XCTAssertEqual(c.state.liveBackground, background)
    }
}
