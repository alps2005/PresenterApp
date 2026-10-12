import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class FormattingCommandTests: XCTestCase {
    /// One item whose presentation has slides s1 and s2, plus one image asset in the project.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let item: PresentationItem
        let presentationID: UUID
        let s1: SlideDocument
        let s2: SlideDocument
        let asset: MediaAsset

        var position1: SlidePosition { SlidePosition(itemID: item.id, slideID: s1.id) }
        var position2: SlidePosition { SlidePosition(itemID: item.id, slideID: s2.id) }

        @MainActor func slide(_ id: UUID) -> SlideDocument? {
            coordinator.project.presentation(withID: presentationID)?.slide(withID: id)
        }
    }

    private func makeFixture() -> Fixture {
        let s1 = SlideDocument.text("One")
        let s2 = SlideDocument.text("Two", role: .title)
        let presentation = PresentationDocument(title: "P", slides: [s1, s2])
        let item = PresentationItem(presentationID: presentation.id)
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "x.jpg", pixelWidth: 4, pixelHeight: 3)
        let project = ProjectDocument(
            name: "Test",
            presentations: [presentation],
            playlist: PlaylistDocument(title: "P", items: [item]),
            mediaAssets: [asset]
        )
        return Fixture(
            coordinator: PresentationCoordinator(project: project),
            item: item, presentationID: presentation.id, s1: s1, s2: s2, asset: asset
        )
    }

    private let red = SlideBackground.color(RGBAColor(red: 1, green: 0, blue: 0))
    private let blue = SlideBackground.color(RGBAColor(red: 0, green: 0, blue: 1))

    // MARK: Text style and position

    func testSetTextStyleChangesOnlyTheStyle() {
        let f = makeFixture()
        let style = TextStyle(fontFamily: "Georgia", fontSize: 72, weight: .bold, color: .black, alignment: .leading)

        XCTAssertEqual(f.coordinator.setTextStyle(style, slideID: f.s1.id, inPresentation: f.presentationID), .applied)

        let element = f.slide(f.s1.id)?.primaryTextElement
        XCTAssertEqual(element?.style, style)
        XCTAssertEqual(element?.text, "One")
        XCTAssertEqual(f.slide(f.s2.id)?.primaryTextElement?.style, .default(for: .title))
    }

    func testSetTextBoxAndResetToFlowLayout() {
        let f = makeFixture()
        let box = TextBox.preset(.bottom)

        f.coordinator.setTextBox(box, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.slide(f.s1.id)?.primaryTextElement?.box, box)

        f.coordinator.setTextBox(nil, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertNil(f.slide(f.s1.id)?.primaryTextElement?.box)
    }

    func testStylingASlideWithoutTextAddsATextElement() {
        let empty = SlideDocument()
        let presentation = PresentationDocument(title: "P", slides: [empty])
        let coordinator = PresentationCoordinator(project: ProjectDocument(name: "T", presentations: [presentation]))
        let style = TextStyle(fontSize: 50)

        XCTAssertEqual(coordinator.setTextStyle(style, slideID: empty.id, inPresentation: presentation.id), .applied)
        XCTAssertEqual(coordinator.project.presentations[0].slides[0].primaryTextElement?.style, style)
    }

    func testApplyTextFormatToAllSlidesCopiesStyleAndBoxButNotText() {
        let f = makeFixture()
        let style = TextStyle(fontFamily: "Avenir", fontSize: 80)
        let box = TextBox.preset(.topLeading)
        f.coordinator.setTextStyle(style, slideID: f.s1.id, inPresentation: f.presentationID)
        f.coordinator.setTextBox(box, slideID: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.coordinator.applyTextFormatToAllSlides(from: f.s1.id, inPresentation: f.presentationID), .applied)

        let other = f.slide(f.s2.id)?.primaryTextElement
        XCTAssertEqual(other?.style, style)
        XCTAssertEqual(other?.box, box)
        XCTAssertEqual(other?.text, "Two")
        XCTAssertEqual(other?.role, .title)
    }

    func testFormattingRejectsUnknownSlideAndPresentation() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.setTextStyle(TextStyle(), slideID: UUID(), inPresentation: f.presentationID),
                       .rejected(.unknownSlide))
        XCTAssertEqual(f.coordinator.setTextBox(nil, slideID: f.s1.id, inPresentation: UUID()),
                       .rejected(.unknownPresentation))
        XCTAssertEqual(f.coordinator.applyTextFormatToAllSlides(from: UUID(), inPresentation: f.presentationID),
                       .rejected(.unknownSlide))
        XCTAssertEqual(f.coordinator.setSlideBackground(red, slideID: UUID(), inPresentation: f.presentationID),
                       .rejected(.unknownSlide))
        XCTAssertEqual(f.coordinator.setPresentationBackground(red, presentationID: UUID()),
                       .rejected(.unknownPresentation))
    }

    // MARK: Backgrounds

    func testBackgroundResolutionPrefersSlideThenPresentationThenDefault() {
        let f = makeFixture()
        XCTAssertNil(f.coordinator.project.renderedSlide(at: f.position1)?.background)

        f.coordinator.setPresentationBackground(red, presentationID: f.presentationID)
        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position1)?.background, red)
        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position2)?.background, red)

        f.coordinator.setSlideBackground(blue, slideID: f.s2.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position1)?.background, red)
        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position2)?.background, blue)

        f.coordinator.setSlideBackground(nil, slideID: f.s2.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position2)?.background, red)
    }

    func testSlideOverrideSurvivesPresentationBackgroundChange() {
        let f = makeFixture()
        f.coordinator.setSlideBackground(blue, slideID: f.s1.id, inPresentation: f.presentationID)
        f.coordinator.setPresentationBackground(red, presentationID: f.presentationID)

        XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position1)?.background, blue)
    }

    func testImageBackgroundRequiresKnownAsset() {
        let f = makeFixture()
        let unknown = SlideBackground.image(ImageBackground(assetID: UUID()))
        let known = SlideBackground.image(ImageBackground(assetID: f.asset.id, dimming: 0.3))

        XCTAssertEqual(f.coordinator.setPresentationBackground(unknown, presentationID: f.presentationID),
                       .rejected(.unknownMediaAsset))
        XCTAssertEqual(f.coordinator.setSlideBackground(unknown, slideID: f.s1.id, inPresentation: f.presentationID),
                       .rejected(.unknownMediaAsset))
        XCTAssertEqual(f.coordinator.setSlideBackground(known, slideID: f.s1.id, inPresentation: f.presentationID),
                       .applied)
        XCTAssertEqual(f.slide(f.s1.id)?.background, known)
    }

    func testAddMediaAssetIsIdempotent() {
        let f = makeFixture()
        let asset = MediaAsset(originalFilename: "a.png", storedFilename: "b.png", pixelWidth: 1, pixelHeight: 1)

        f.coordinator.addMediaAsset(asset)
        f.coordinator.addMediaAsset(asset)

        XCTAssertEqual(f.coordinator.project.mediaAssets.filter { $0.id == asset.id }.count, 1)
        XCTAssertEqual(f.coordinator.setPresentationBackground(.image(ImageBackground(assetID: asset.id)),
                                                               presentationID: f.presentationID), .applied)
    }

    // MARK: Live snapshot

    func testPresentationBackgroundChangeDoesNotLeakOntoLiveOutput() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        let sceneBefore = f.coordinator.audienceScene

        f.coordinator.setPresentationBackground(red, presentationID: f.presentationID)

        XCTAssertEqual(f.coordinator.audienceScene, sceneBefore)
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)

        f.coordinator.takeLive()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1, background: red)))
        XCTAssertFalse(f.coordinator.liveSlideHasPendingEdits)
    }

    func testStyleChangeDoesNotLeakOntoLiveOutput() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)

        f.coordinator.setTextStyle(TextStyle(fontSize: 40), slideID: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1)))
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)
    }

    func testPreviewAndUpNextCarryResolvedBackground() {
        let f = makeFixture()
        f.coordinator.setPresentationBackground(red, presentationID: f.presentationID)
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        f.coordinator.cueSlide(f.s2.id, inItem: f.item.id)

        XCTAssertEqual(f.coordinator.previewSlide?.background, red)
        XCTAssertEqual(f.coordinator.upNextSlide?.background, red)
    }
}
