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

    func testFormattingAndMediaRoundTripThroughJSON() throws {
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "a.jpg", pixelWidth: 1920, pixelHeight: 1080)
        let text = TextElement(
            text: "Hello",
            role: .title,
            style: TextStyle(fontFamily: "Georgia", fontSize: 120, weight: .heavy, isItalic: true,
                             color: RGBAColor(red: 1, green: 0.5, blue: 0, alpha: 0.9), alignment: .trailing,
                             lineSpacing: 12, hasShadow: false),
            box: TextBox.preset(.bottomTrailing, margin: 0.05)
        )
        let slide = SlideDocument(elements: [.text(text)],
                                  background: .image(ImageBackground(assetID: asset.id, scaling: .fit, dimming: 0.4)))
        let presentation = PresentationDocument(title: "P", slides: [slide], background: .color(.black))
        let project = ProjectDocument(name: "P", presentations: [presentation], mediaAssets: [asset])

        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(decoded, project)
    }

    /// JSON written before styling, backgrounds and media existed still loads, with today's defaults.
    func testDecodesDocumentsWithoutFormattingFields() throws {
        let json = """
        {
          "id": "8E4B1C2A-0000-4000-8000-000000000001",
          "name": "Old",
          "schemaVersion": 1,
          "presentations": [{
            "id": "8E4B1C2A-0000-4000-8000-000000000002",
            "title": "Old Presentation",
            "createdAt": 0,
            "updatedAt": 0,
            "slides": [{
              "id": "8E4B1C2A-0000-4000-8000-000000000003",
              "elements": [{"text": {"_0": {
                "id": "8E4B1C2A-0000-4000-8000-000000000004", "text": "Hi", "role": "title"
              }}}]
            }]
          }],
          "playlist": {"id": "8E4B1C2A-0000-4000-8000-000000000005", "title": "S", "items": []}
        }
        """

        let project = try JSONDecoder().decode(ProjectDocument.self, from: Data(json.utf8))

        XCTAssertTrue(project.mediaAssets.isEmpty)
        let presentation = try XCTUnwrap(project.presentations.first)
        XCTAssertNil(presentation.background)
        let slide = try XCTUnwrap(presentation.slides.first)
        XCTAssertNil(slide.background)
        let element = try XCTUnwrap(slide.primaryTextElement)
        XCTAssertEqual(element.style, .default(for: .title))
        XCTAssertNil(element.box)
    }

    /// Unstyled text must render exactly as it did before styling existed.
    func testDefaultStylesMatchThePreviousRenderer() {
        XCTAssertEqual(TextStyle.default(for: .title).fontSize, 140)
        XCTAssertEqual(TextStyle.default(for: .title).weight, .bold)
        XCTAssertEqual(TextStyle.default(for: .body).fontSize, 96)
        XCTAssertEqual(TextStyle.default(for: .body).weight, .semibold)
        XCTAssertEqual(TextStyle.default(for: .caption).fontSize, 56)
        XCTAssertEqual(TextStyle.default(for: .caption).weight, .regular)
        for role in TextRole.allCases {
            let style = TextStyle.default(for: role)
            XCTAssertNil(style.fontFamily)
            XCTAssertEqual(style.color, .white)
            XCTAssertEqual(style.alignment, .center)
            XCTAssertTrue(style.hasShadow)
        }
    }
}
