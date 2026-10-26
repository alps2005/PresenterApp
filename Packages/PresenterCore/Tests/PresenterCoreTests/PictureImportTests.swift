import XCTest
@testable import PresenterCore

@MainActor
final class PictureImportTests: XCTestCase {
    func testPicturesBecomeOneSlideEachOverBlack() throws {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let pages = (1...3).map { MediaAsset(originalFilename: "Sermon page \($0).png", storedFilename: "\($0).png", pixelWidth: 1920, pixelHeight: 1080) }
        pages.forEach { c.addMediaAsset($0) }

        let item = try XCTUnwrap(c.addPresentation(title: "Sermon", pictures: pages.map(\.id)))
        let deck = try XCTUnwrap(c.project.presentation(forItem: item.id))
        XCTAssertEqual(deck.title, "Sermon")
        XCTAssertEqual(deck.kind, .presentation)
        XCTAssertEqual(deck.background, .color(.black))
        XCTAssertEqual(deck.slides.map(\.background), pages.map { .image(ImageBackground(assetID: $0.id, scaling: .fit)) })
        XCTAssertTrue(deck.slides.allSatisfy(\.elements.isEmpty))
        XCTAssertEqual(c.state.selectedItemID, item.id)
        XCTAssertEqual(c.undoActionName, "Import Pictures")

        c.undo()
        XCTAssertNil(c.project.presentation(withID: deck.id))
        XCTAssertEqual(c.project.mediaAssets.count, 3, "Undo keeps the imported files")
        XCTAssertNil(c.addPresentation(title: "None", pictures: []))
        XCTAssertNil(c.addPresentation(title: "Unknown", pictures: [UUID()]))
    }
}
