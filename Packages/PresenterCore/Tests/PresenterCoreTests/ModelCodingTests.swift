import Foundation
import XCTest
@testable import PresenterCore

final class ModelCodingTests: XCTestCase {
    func testProjectRoundTripsThroughJSONPreservingIDs() throws {
        let project = ProjectDocument.sample()

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)

        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.schemaVersion, ProjectDocument.currentSchemaVersion)
        XCTAssertEqual(decoded.playlist.items.map(\.presentationID), project.presentations.map(\.id))
    }

    func testSlidePlainTextJoinsTextElements() {
        let slide = SlideDocument(elements: [
            .text(TextElement(text: "Title", role: .title)),
            .text(TextElement(text: "Body")),
        ])
        XCTAssertEqual(slide.plainText, "Title\nBody")
    }

    func testMissingPresentationResolvesToNil() {
        let orphan = PresentationItem(presentationID: UUID())
        let project = ProjectDocument(name: "P", playlist: PlaylistDocument(title: "P", items: [orphan]))
        XCTAssertNil(project.presentation(forItem: orphan.id))
        XCTAssertNil(project.slide(at: SlidePosition(itemID: orphan.id, slideID: UUID())))
    }
}
