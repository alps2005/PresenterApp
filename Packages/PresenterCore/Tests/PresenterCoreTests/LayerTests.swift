import Foundation
import XCTest
@testable import PresenterCore

/// The audience output's background layer, which transparent slides keep (ProPresenter's empty background).
@MainActor
final class LayerTests: XCTestCase {
    /// One item whose presentation has an image slide (s1) followed by two transparent slides (s2, s3)
    /// and an opaque colour slide (s4).
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let item: PresentationItem
        let s1, s2, s3, s4: SlideDocument
        let image: SlideBackground
        let red: SlideBackground
    }

    private func makeFixture() -> Fixture {
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "s.jpg", pixelWidth: 4, pixelHeight: 3)
        let image = SlideBackground.image(ImageBackground(assetID: asset.id))
        let red = SlideBackground.color(RGBAColor(red: 1, green: 0, blue: 0))
        let s1 = SlideDocument(elements: [.text(TextElement(text: "One"))], background: image)
        let s2 = SlideDocument(elements: [.text(TextElement(text: "Two"))], background: .transparent)
        let s3 = SlideDocument(elements: [.text(TextElement(text: "Three"))], background: .transparent)
        let s4 = SlideDocument(elements: [.text(TextElement(text: "Four"))], background: red)
        let presentation = PresentationDocument(title: "P", slides: [s1, s2, s3, s4])
        let item = PresentationItem(presentationID: presentation.id)
        let project = ProjectDocument(name: "T", presentations: [presentation],
                                      playlist: PlaylistDocument(title: "P", items: [item]), mediaAssets: [asset])
        return Fixture(coordinator: PresentationCoordinator(project: project), item: item,
                       s1: s1, s2: s2, s3: s3, s4: s4, image: image, red: red)
    }

    func testTransparentSlidesKeepTheBackgroundAlreadyOnScreen() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s2, background: f.image)))
        f.coordinator.nextSlide()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s3, background: f.image)))
    }

    func testOpaqueSlideReplacesTheBackground() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s3.id, inItem: f.item.id)
        XCTAssertEqual(f.coordinator.state.liveBackground, nil, "nothing set a background yet: app default")
        f.coordinator.takeLive(slideID: f.s4.id, inItem: f.item.id)
        XCTAssertEqual(f.coordinator.state.liveBackground, f.red)
        f.coordinator.takeLive(slideID: f.s2.id, inItem: f.item.id)
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s2, background: f.red)))
    }

    func testClearSlideKeepsBackgroundAndClearBackgroundKeepsSlide() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)

        XCTAssertEqual(f.coordinator.clearOutput(), .applied)
        XCTAssertEqual(f.coordinator.audienceScene, .background(f.image))

        XCTAssertEqual(f.coordinator.restoreOutput(), .applied)
        XCTAssertEqual(f.coordinator.clearBackground(), .applied)
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1, background: nil)))
        XCTAssertEqual(f.coordinator.clearBackground(), .rejected(.nothingToClear))

        XCTAssertTrue(f.coordinator.canRestore)
        f.coordinator.restoreOutput()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1, background: f.image)))
    }

    func testClearAllThenRestoreBringsBothBack() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)

        XCTAssertEqual(f.coordinator.clearAll(), .applied)
        XCTAssertEqual(f.coordinator.audienceScene, .empty)
        XCTAssertEqual(f.coordinator.clearAll(), .rejected(.nothingLive))

        f.coordinator.restoreOutput()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1, background: f.image)))
        XCTAssertFalse(f.coordinator.canRestore)
    }

    func testBlackoutCoversBothLayers() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        f.coordinator.clearOutput()
        f.coordinator.blackout()
        XCTAssertEqual(f.coordinator.audienceScene, .black)
        f.coordinator.restoreOutput()
        XCTAssertEqual(f.coordinator.audienceScene, .slide(RenderedSlide(slide: f.s1, background: f.image)))
    }

    func testTransparentPresentationBackgroundIsInheritedBySlides() {
        let s1 = SlideDocument.text("A")
        var s2 = SlideDocument.text("B")
        s2.background = .color(.black)
        let presentation = PresentationDocument(title: "P", slides: [s2, s1], background: .transparent)
        let item = PresentationItem(presentationID: presentation.id)
        let coordinator = PresentationCoordinator(project: ProjectDocument(
            name: "T", presentations: [presentation], playlist: PlaylistDocument(title: "P", items: [item])
        ))

        coordinator.takeLive(slideID: s2.id, inItem: item.id)
        coordinator.nextSlide()

        XCTAssertEqual(coordinator.audienceScene, .slide(RenderedSlide(slide: s1, background: .color(.black))))
    }

    func testEditingTheBackgroundDoesNotChangeTheLiveLayer() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        let presentationID = f.coordinator.project.presentations[0].id

        f.coordinator.setSlideBackground(f.red, slideID: f.s1.id, inPresentation: presentationID)

        XCTAssertEqual(f.coordinator.state.liveBackground, f.image)
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)
    }

    func testUpNextPreviewShowsTransparentSlidesOverTheCurrentBackground() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        let upNext = f.coordinator.upNextSlide!

        XCTAssertEqual(upNext.background, .transparent)
        XCTAssertEqual(f.coordinator.outputPreview(of: upNext).background, f.image)
    }

    func testTransparentBackgroundRoundTripsAndOldFilesStillLoad() throws {
        let slide = SlideDocument(elements: [.text(TextElement(text: "x"))], background: .transparent)
        let project = ProjectDocument(name: "P", presentations: [PresentationDocument(title: "P", slides: [slide])])
        XCTAssertEqual(try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(project)), project)
    }
}
