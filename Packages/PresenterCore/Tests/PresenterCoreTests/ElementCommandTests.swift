import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class ElementCommandTests: XCTestCase {
    /// One item whose presentation has slides s1 ("One") and s2 ("Two"), plus one image asset.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let item: PresentationItem
        let presentationID: UUID
        let s1: SlideDocument
        let s2: SlideDocument
        let asset: MediaAsset

        @MainActor var slides: [SlideDocument] {
            coordinator.project.presentation(withID: presentationID)?.slides ?? []
        }

        @MainActor func slide(_ id: UUID) -> SlideDocument? {
            coordinator.project.presentation(withID: presentationID)?.slide(withID: id)
        }
    }

    private func makeFixture() -> Fixture {
        let s1 = SlideDocument.text("One")
        let s2 = SlideDocument.text("Two")
        let presentation = PresentationDocument(title: "P", slides: [s1, s2])
        let item = PresentationItem(presentationID: presentation.id)
        let asset = MediaAsset(originalFilename: "logo.png", storedFilename: "l.png", pixelWidth: 400, pixelHeight: 200)
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

    private let box = NormalizedRect.centered(width: 0.4, height: 0.3)

    func testAddedElementsStackOnTop() {
        let f = makeFixture()
        let shape = SlideElement.shape(ShapeElement(kind: .ellipse, frame: box))
        let image = SlideElement.image(ImageElement(assetID: f.asset.id, frame: box))

        XCTAssertEqual(f.coordinator.addElement(shape, toSlide: f.s1.id, inPresentation: f.presentationID), .applied)
        XCTAssertEqual(f.coordinator.addElement(image, toSlide: f.s1.id, inPresentation: f.presentationID), .applied)

        XCTAssertEqual(f.slide(f.s1.id)?.elements.map(\.id), [f.s1.elements[0].id, shape.id, image.id])
    }

    func testImageWithUnknownAssetIsRejected() {
        let f = makeFixture()
        let image = SlideElement.image(ImageElement(assetID: UUID(), frame: box))

        XCTAssertEqual(f.coordinator.addElement(image, toSlide: f.s1.id, inPresentation: f.presentationID),
                       .rejected(.unknownMediaAsset))
        XCTAssertEqual(f.slide(f.s1.id)?.elements.count, 1)
    }

    func testUpdateReplacesElementInPlace() {
        let f = makeFixture()
        var shape = ShapeElement(kind: .rectangle, frame: box)
        f.coordinator.addElement(.shape(shape), toSlide: f.s1.id, inPresentation: f.presentationID)

        shape.fill = nil
        shape.stroke = .white
        XCTAssertEqual(f.coordinator.updateElement(.shape(shape), slideID: f.s1.id, inPresentation: f.presentationID), .applied)

        XCTAssertEqual(f.slide(f.s1.id)?.element(withID: shape.id), .shape(shape))
        XCTAssertEqual(f.slide(f.s1.id)?.elements.count, 2)
    }

    func testUpdatingOrDeletingMissingElementIsRejected() {
        let f = makeFixture()
        let stray = SlideElement.shape(ShapeElement(kind: .rectangle, frame: box))

        XCTAssertEqual(f.coordinator.updateElement(stray, slideID: f.s1.id, inPresentation: f.presentationID),
                       .rejected(.unknownElement))
        XCTAssertEqual(f.coordinator.deleteElement(stray.id, slideID: f.s1.id, inPresentation: f.presentationID),
                       .rejected(.unknownElement))
        XCTAssertEqual(f.coordinator.deleteElement(stray.id, slideID: UUID(), inPresentation: f.presentationID),
                       .rejected(.unknownSlide))
    }

    func testDeleteRemovesElement() {
        let f = makeFixture()
        let textID = f.s1.elements[0].id

        XCTAssertEqual(f.coordinator.deleteElement(textID, slideID: f.s1.id, inPresentation: f.presentationID), .applied)
        XCTAssertEqual(f.slide(f.s1.id)?.elements, [])
    }

    func testReorderMovesThroughDrawingOrder() {
        let f = makeFixture()
        let a = f.s1.elements[0].id
        let b = SlideElement.shape(ShapeElement(kind: .rectangle, frame: box))
        let c = SlideElement.shape(ShapeElement(kind: .ellipse, frame: box))
        f.coordinator.addElement(b, toSlide: f.s1.id, inPresentation: f.presentationID)
        f.coordinator.addElement(c, toSlide: f.s1.id, inPresentation: f.presentationID)
        func order() -> [UUID] { f.slide(f.s1.id)?.elements.map(\.id) ?? [] }

        f.coordinator.reorderElement(a, .forward, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(order(), [b.id, a, c.id])
        f.coordinator.reorderElement(a, .front, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(order(), [b.id, c.id, a])
        f.coordinator.reorderElement(a, .back, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(order(), [a, b.id, c.id])
        f.coordinator.reorderElement(a, .backward, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(order(), [a, b.id, c.id])
    }

    func testEditingLiveSlideElementsDoesNotChangeAudience() {
        let f = makeFixture()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        let before = f.coordinator.audienceScene

        f.coordinator.addElement(.shape(ShapeElement(kind: .ellipse, frame: box)), toSlide: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.coordinator.audienceScene, before)
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)
    }

    func testDuplicateInsertsOffsetCopyAboveOriginal() {
        let f = makeFixture()
        let shape = ShapeElement(kind: .rectangle, frame: box)
        f.coordinator.addElement(.shape(shape), toSlide: f.s1.id, inPresentation: f.presentationID)

        let copy = f.coordinator.duplicateElement(shape.id, slideID: f.s1.id, inPresentation: f.presentationID)

        let elements = f.slide(f.s1.id)?.elements ?? []
        XCTAssertEqual(elements.map(\.id), [f.s1.elements[0].id, shape.id, copy?.id].compactMap { $0 })
        XCTAssertNotEqual(copy?.id, shape.id)
        XCTAssertEqual(copy?.frame?.x ?? 0, box.x + 20.0 / 1920, accuracy: 1e-9)
        XCTAssertEqual(copy?.frame?.y ?? 0, box.y + 20.0 / 1080, accuracy: 1e-9)
        XCTAssertNil(f.coordinator.duplicateElement(UUID(), slideID: f.s1.id, inPresentation: f.presentationID))
        XCTAssertEqual(f.coordinator.lastRejection, .unknownElement)
    }

    /// Text the theme places (Scripture puts verses top left) is copied where it's drawn, as its own place, so the
    /// copy sits beside the original instead of exactly on it.
    func testDuplicatingThemedTextOffsetsTheThemedPlace() throws {
        let theme = try XCTUnwrap(Theme.presets().first { $0.name == "Scripture" })
        let verse = TextElement(text: "In the beginning")
        let slide = SlideDocument(elements: [.text(verse)])
        var presentation = PresentationDocument(title: "Genesis", slides: [slide])
        presentation.themeID = theme.id
        var project = ProjectDocument(name: "T", presentations: [presentation], playlist: PlaylistDocument(title: "S", items: []))
        project.themes = [theme]
        let c = PresentationCoordinator(project: project)

        let copy = try XCTUnwrap(c.duplicateElement(verse.id, slideID: slide.id, inPresentation: presentation.id))

        let themedBox = try XCTUnwrap(theme.body.box?.frame)
        let drawn = c.project.rendered(c.project.presentations[0].slides[0], in: c.project.presentations[0]).slide
        XCTAssertEqual(drawn.elements[0].frame, themedBox, "The original still follows the theme")
        let drawnCopy = try XCTUnwrap(drawn.element(withID: copy.id)?.frame)
        XCTAssertEqual(drawnCopy.x, themedBox.x + 20.0 / 1920, accuracy: 1e-9)
        XCTAssertEqual(drawnCopy.y, themedBox.y + 20.0 / 1080, accuracy: 1e-9)
        guard case .text(let copiedText) = copy else { return XCTFail("Not text") }
        XCTAssertTrue(copiedText.overrides.contains(.box))
        XCTAssertFalse(copiedText.overrides.contains(.style), "The copy still takes its look from the theme")
    }

    func testDuplicatedFlowTextStaysUnboxed() {
        let text = SlideElement.text(TextElement(text: "Hi"))
        let copy = text.duplicated(offsetBy: 0.1, 0.1)
        XCTAssertNotEqual(copy.id, text.id)
        XCTAssertNil(copy.frame)
    }

    func testMoveSlidesReordersPresentation() {
        let f = makeFixture()

        XCTAssertEqual(f.coordinator.moveSlides(inPresentation: f.presentationID, fromOffsets: IndexSet(integer: 1), toOffset: 0), .applied)
        XCTAssertEqual(f.slides.map(\.id), [f.s2.id, f.s1.id])

        XCTAssertEqual(f.coordinator.moveSlides(inPresentation: f.presentationID, fromOffsets: IndexSet(integer: 4), toOffset: 0),
                       .rejected(.unknownSlide))
    }

    func testInsertSlideAfterLeavesCueAlone() {
        let f = makeFixture()
        f.coordinator.cueSlide(f.s2.id, inItem: f.item.id)

        let inserted = f.coordinator.insertSlide(after: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.slides.map(\.id), [f.s1.id, inserted?.id, f.s2.id].compactMap { $0 })
        XCTAssertEqual(f.coordinator.state.preview?.slideID, f.s2.id)
        XCTAssertNil(f.coordinator.insertSlide(after: nil, inPresentation: UUID()))
    }

    func testTransitionsSetAndApplyToAll() {
        let f = makeFixture()

        f.coordinator.setTransition(.dissolve(duration: 1), slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.slide(f.s1.id)?.transition, .dissolve(duration: 1))
        XCTAssertNil(f.slide(f.s2.id)?.transition)

        f.coordinator.applyTransitionToAllSlides(from: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.slides.map(\.transition), [.dissolve(duration: 1), .dissolve(duration: 1)])

        f.coordinator.setTransition(nil, slideID: f.s2.id, inPresentation: f.presentationID)
        XCTAssertNil(f.slide(f.s2.id)?.transition)
    }

    func testNotesEmptyTextClears() {
        let f = makeFixture()
        f.coordinator.setNotes("Pause here", slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(f.slide(f.s1.id)?.notes, "Pause here")
        f.coordinator.setNotes("", slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertNil(f.slide(f.s1.id)?.notes)
    }

    func testSettingFrameOnFlowTextGivesItABox() {
        var element = SlideElement.text(TextElement(text: "Hi"))
        XCTAssertNil(element.frame)

        element.frame = box
        XCTAssertEqual(element.frame, box)
        guard case .text(let text) = element else { return XCTFail() }
        XCTAssertEqual(text.box?.verticalAlignment, .center)
    }

    func testClampKeepsRectInsideCanvas() {
        let rect = NormalizedRect(x: 0.9, y: -0.2, width: 0.3, height: 0.001).clampedToCanvas()
        XCTAssertEqual(rect.x, 0.7, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.height, 0.02, accuracy: 1e-9)
    }
}
