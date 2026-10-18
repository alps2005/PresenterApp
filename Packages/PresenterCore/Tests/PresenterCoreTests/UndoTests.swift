import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class UndoTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000)

    private func makeCoordinator() -> (PresentationCoordinator, PresentationItem, PresentationDocument) {
        let presentation = PresentationDocument(title: "P", slides: [.text("One"), .text("Two")])
        let item = PresentationItem(presentationID: presentation.id)
        let coordinator = PresentationCoordinator(project: ProjectDocument(
            name: "T", presentations: [presentation], playlist: PlaylistDocument(title: "P", items: [item])
        ))
        coordinator.now = { [unowned self] in clock }
        return (coordinator, item, presentation)
    }

    private func slides(_ coordinator: PresentationCoordinator, _ presentationID: UUID) -> [SlideDocument] {
        coordinator.project.presentation(withID: presentationID)?.slides ?? []
    }

    func testUndoAndRedoAnElementEdit() {
        let (c, _, p) = makeCoordinator()
        let slideID = p.slides[0].id
        let shape = SlideElement.shape(ShapeElement(kind: .ellipse, frame: .centered(width: 0.2, height: 0.2)))

        c.addElement(shape, toSlide: slideID, inPresentation: p.id)
        XCTAssertEqual(c.undoActionName, "Add")

        c.undo()
        XCTAssertNil(slides(c, p.id)[0].element(withID: shape.id))
        XCTAssertFalse(c.canUndo)
        XCTAssertEqual(c.redoActionName, "Add")

        c.redo()
        XCTAssertNotNil(slides(c, p.id)[0].element(withID: shape.id))
        XCTAssertTrue(c.canUndo)
        XCTAssertFalse(c.canRedo)
    }

    func testTypingCoalescesIntoOneUndoUntilAPause() {
        let (c, _, p) = makeCoordinator()
        let slideID = p.slides[0].id

        c.updateSlideText("O", slideID: slideID, inPresentation: p.id)
        clock += 0.3
        c.updateSlideText("On", slideID: slideID, inPresentation: p.id)
        clock += 0.3
        c.updateSlideText("One!", slideID: slideID, inPresentation: p.id)
        clock += 5
        c.updateSlideText("One!!", slideID: slideID, inPresentation: p.id)

        c.undo()
        XCTAssertEqual(slides(c, p.id)[0].primaryText, "One!")
        c.undo()
        XCTAssertEqual(slides(c, p.id)[0].primaryText, "One")
        XCTAssertFalse(c.canUndo)
    }

    func testEditsThatChangeNothingAreNotRecorded() {
        let (c, _, p) = makeCoordinator()
        c.updateSlideText("One", slideID: p.slides[0].id, inPresentation: p.id)
        c.renamePresentation(p.id, to: "P")
        XCTAssertFalse(c.canUndo)
    }

    func testRejectedCommandsAreNotRecorded() {
        let (c, _, p) = makeCoordinator()
        c.deleteElement(UUID(), slideID: p.slides[0].id, inPresentation: p.id)
        XCTAssertFalse(c.canUndo)
    }

    func testUndoNeverChangesTheAudienceOutput() {
        let (c, item, p) = makeCoordinator()
        c.takeLive(slideID: p.slides[0].id, inItem: item.id)
        let live = c.audienceScene

        c.deleteSlide(p.slides[0].id, inPresentation: p.id)
        c.undo()
        c.redo()

        XCTAssertEqual(c.audienceScene, live)
        XCTAssertFalse(c.canRedo)
    }

    func testUndoClearsACueThatNoLongerExists() {
        let (c, item, p) = makeCoordinator()
        let added = c.insertSlide(after: p.slides[1].id, inPresentation: p.id)!
        c.cueSlide(added.id, inItem: item.id)

        c.undo()

        XCTAssertNil(c.state.preview)
        XCTAssertEqual(slides(c, p.id).count, 2)
    }

    func testNewEditClearsRedo() {
        let (c, _, p) = makeCoordinator()
        c.renamePresentation(p.id, to: "A")
        c.undo()
        XCTAssertTrue(c.canRedo)
        c.setNotes("Hi", slideID: p.slides[0].id, inPresentation: p.id)
        XCTAssertFalse(c.canRedo)
    }

    func testOpeningAnotherProjectClearsHistory() {
        let (c, _, p) = makeCoordinator()
        c.renamePresentation(p.id, to: "A")
        c.replaceProject(.sample())
        XCTAssertFalse(c.canUndo)
        XCTAssertFalse(c.canRedo)
    }

    func testCommandThatCallsAnotherRecordsOnce() {
        let (c, _, p) = makeCoordinator()
        let shape = ShapeElement(kind: .rectangle, frame: .centered(width: 0.2, height: 0.2))
        c.addElement(.shape(shape), toSlide: p.slides[0].id, inPresentation: p.id)
        clock += 5
        c.duplicateElement(shape.id, slideID: p.slides[0].id, inPresentation: p.id)

        c.undo()
        XCTAssertEqual(slides(c, p.id)[0].elements.count, 2)
        c.undo()
        XCTAssertEqual(slides(c, p.id)[0].elements.count, 1)
    }

    func testUndoKeepsMediaImportedAfterTheEdit() {
        let (c, _, p) = makeCoordinator()
        c.renamePresentation(p.id, to: "Renamed")
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "s.jpg", pixelWidth: 4, pixelHeight: 3)
        c.addMediaAsset(asset)

        c.undo()
        XCTAssertEqual(c.project.presentation(withID: p.id)?.title, "P")
        XCTAssertNotNil(c.project.asset(withID: asset.id))

        c.redo()
        XCTAssertEqual(c.project.presentation(withID: p.id)?.title, "Renamed")
        XCTAssertNotNil(c.project.asset(withID: asset.id))
    }

    func testUndoingABackgroundKeepsItsImportedImage() {
        let (c, _, p) = makeCoordinator()
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "s.jpg", pixelWidth: 4, pixelHeight: 3)
        c.addMediaAsset(asset)
        c.setSlideBackground(.image(ImageBackground(assetID: asset.id)), slideID: p.slides[0].id, inPresentation: p.id)

        c.undo()
        XCTAssertNil(slides(c, p.id)[0].background)
        XCTAssertEqual(c.project.mediaAssets.map(\.id), [asset.id])
    }

    // MARK: - Deleting media

    private func importAsset(_ c: PresentationCoordinator, _ name: String = "sky.jpg") -> MediaAsset {
        let asset = MediaAsset(originalFilename: name, storedFilename: "\(UUID().uuidString).jpg", pixelWidth: 4, pixelHeight: 3)
        c.addMediaAsset(asset)
        return asset
    }

    func testDeletingMediaRemovesItFromBackgroundsImagesAndThemes() throws {
        let (c, _, p) = makeCoordinator()
        let asset = importAsset(c)
        let other = importAsset(c, "sea.jpg")
        let image = SlideElement.image(ImageElement(assetID: asset.id, frame: .centered(width: 0.2, height: 0.2)))
        c.setPresentationBackground(.image(ImageBackground(assetID: asset.id)), presentationID: p.id)
        c.setSlideBackground(.image(ImageBackground(assetID: other.id)), slideID: p.slides[0].id, inPresentation: p.id)
        c.setSlideBackground(.video(VideoBackground(assetID: asset.id)), slideID: p.slides[1].id, inPresentation: p.id)
        c.addElement(image, toSlide: p.slides[0].id, inPresentation: p.id)
        var theme = try XCTUnwrap(c.project.themes.first)
        theme.background = .image(ImageBackground(assetID: asset.id))
        c.updateTheme(theme)
        XCTAssertEqual(c.project.presentationsUsing(asset: asset.id).map(\.id), [p.id])
        XCTAssertEqual(c.project.themesUsing(asset: asset.id).map(\.id), [theme.id])

        XCTAssertTrue(c.removeMediaAsset(asset.id).isApplied)

        XCTAssertNil(c.project.asset(withID: asset.id))
        XCTAssertNotNil(c.project.asset(withID: other.id))
        let presentation = try XCTUnwrap(c.project.presentation(withID: p.id))
        XCTAssertNil(presentation.background)
        XCTAssertEqual(presentation.slides[0].background?.assetID, other.id, "Other media is left alone")
        XCTAssertNil(presentation.slides[1].background)
        XCTAssertTrue(presentation.slides[0].elements.allSatisfy { $0.assetID == nil })
        XCTAssertNil(c.project.theme(withID: theme.id)?.background)
        XCTAssertTrue(c.project.presentationsUsing(asset: asset.id).isEmpty)
        XCTAssertEqual(c.undoActionName, "Delete Media")
    }

    func testUndoBringsDeletedMediaBackAndRedoDeletesItAgain() {
        let (c, _, p) = makeCoordinator()
        let asset = importAsset(c)
        c.setSlideBackground(.image(ImageBackground(assetID: asset.id)), slideID: p.slides[0].id, inPresentation: p.id)
        c.removeMediaAsset(asset.id)

        c.undo()
        XCTAssertNotNil(c.project.asset(withID: asset.id))
        XCTAssertEqual(slides(c, p.id)[0].background?.assetID, asset.id)

        c.redo()
        XCTAssertNil(c.project.asset(withID: asset.id))
        XCTAssertNil(slides(c, p.id)[0].background)
    }

    func testMediaImportedAfterADeleteSurvivesUndoingIt() {
        let (c, _, _) = makeCoordinator()
        let deleted = importAsset(c)
        c.removeMediaAsset(deleted.id)
        let later = importAsset(c, "sea.jpg")

        c.undo()
        XCTAssertEqual(Set(c.project.mediaAssets.map(\.id)), [deleted.id, later.id])
        c.redo()
        XCTAssertEqual(c.project.mediaAssets.map(\.id), [later.id])
    }

    func testDeletingUnknownMediaIsRejected() {
        let (c, _, _) = makeCoordinator()
        XCTAssertEqual(c.removeMediaAsset(UUID()), .rejected(.unknownMediaAsset))
        XCTAssertFalse(c.canUndo)
    }
}
