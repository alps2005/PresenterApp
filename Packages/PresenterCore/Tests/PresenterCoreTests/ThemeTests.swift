import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class ThemeTests: XCTestCase {
    /// One item whose presentation has a body slide and a title slide, a theme it doesn't follow yet, and an image.
    private struct Fixture {
        let coordinator: PresentationCoordinator
        let item: PresentationItem
        let presentationID: UUID
        let s1: SlideDocument
        let s2: SlideDocument
        let theme: Theme
        let asset: MediaAsset

        var position1: SlidePosition { SlidePosition(itemID: item.id, slideID: s1.id) }

        @MainActor var presentation: PresentationDocument {
            coordinator.project.presentation(withID: presentationID)!
        }

        @MainActor func stored(_ slideID: UUID) -> TextElement? {
            presentation.slide(withID: slideID)?.primaryTextElement
        }

        /// The text as it's drawn: themed.
        @MainActor func drawn(_ slideID: UUID) -> TextElement? {
            coordinator.project.rendered(presentation.slide(withID: slideID)!, in: presentation).slide.primaryTextElement
        }
    }

    private static let themeBody = TextStyle(fontFamily: "Georgia", fontSize: 72, weight: .regular, alignment: .leading)
    private static let themeBox = TextBox.preset(.topLeading)
    private static let themeBackground = SlideBackground.color(RGBAColor(red: 0, green: 0.2, blue: 0))

    private func makeFixture() -> Fixture {
        let s1 = SlideDocument.text("One")
        let s2 = SlideDocument.text("Two", role: .title)
        let presentation = PresentationDocument(title: "P", slides: [s1, s2])
        let item = PresentationItem(presentationID: presentation.id)
        let asset = MediaAsset(originalFilename: "sky.jpg", storedFilename: "x.jpg", pixelWidth: 4, pixelHeight: 3)
        var theme = Theme(name: "Test")
        theme.body = ThemeText(style: Self.themeBody, box: Self.themeBox)
        theme.background = Self.themeBackground
        let project = ProjectDocument(
            name: "Test",
            presentations: [presentation],
            playlist: PlaylistDocument(title: "P", items: [item]),
            mediaAssets: [asset],
            themes: [theme]
        )
        return Fixture(coordinator: PresentationCoordinator(project: project), item: item,
                       presentationID: presentation.id, s1: s1, s2: s2, theme: theme, asset: asset)
    }

    private func themed() -> Fixture {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.setPresentationTheme(f.theme.id, presentationID: f.presentationID), .applied)
        return f
    }

    // MARK: Resolution

    func testTextFollowsItsRolesLookInTheTheme() {
        let f = themed()

        XCTAssertEqual(f.drawn(f.s1.id)?.style, Self.themeBody)
        XCTAssertEqual(f.drawn(f.s1.id)?.box, Self.themeBox)
        XCTAssertEqual(f.drawn(f.s2.id)?.style, .default(for: .title), "the test theme's title is the default look")
        XCTAssertEqual(f.drawn(f.s1.id)?.text, "One")
    }

    func testBackgroundIsTheSlidesThenThePresentationsThenTheThemes() {
        let f = themed()
        let red = SlideBackground.color(RGBAColor(red: 1, green: 0, blue: 0))
        let blue = SlideBackground.color(RGBAColor(red: 0, green: 0, blue: 1))
        func background() -> SlideBackground? { f.coordinator.project.renderedSlide(at: f.position1)?.background }

        XCTAssertEqual(background(), Self.themeBackground)
        f.coordinator.setPresentationBackground(blue, presentationID: f.presentationID)
        XCTAssertEqual(background(), blue)
        f.coordinator.setSlideBackground(red, slideID: f.s1.id, inPresentation: f.presentationID)
        XCTAssertEqual(background(), red)
    }

    func testWithoutAThemeTextIsDrawnAsStored() {
        let f = makeFixture()
        XCTAssertEqual(f.drawn(f.s1.id), f.stored(f.s1.id))
        XCTAssertNil(f.coordinator.project.renderedSlide(at: f.position1)?.background)
    }

    func testChangingTheThemeChangesEverySlideThatFollowsIt() {
        let f = themed()
        var theme = f.theme
        theme.body.style.fontSize = 50

        XCTAssertEqual(f.coordinator.updateTheme(theme), .applied)

        XCTAssertEqual(f.drawn(f.s1.id)?.style.fontSize, 50)
    }

    // MARK: Formatting by hand

    func testStylingTextByHandKeepsItWhenTheThemeChanges() {
        let f = themed()
        var style = Self.themeBody
        style.color = .black

        f.coordinator.setTextStyle(style, slideID: f.s1.id, inPresentation: f.presentationID)
        var theme = f.theme
        theme.body.style.fontSize = 50
        f.coordinator.updateTheme(theme)

        XCTAssertEqual(f.stored(f.s1.id)?.overrides, [.style])
        XCTAssertEqual(f.drawn(f.s1.id)?.style, style)
        XCTAssertEqual(f.drawn(f.s1.id)?.box, Self.themeBox, "only the style was set by hand")
    }

    func testDraggingThemedTextOverridesOnlyItsPosition() throws {
        let f = themed()
        var element = try XCTUnwrap(f.drawn(f.s1.id))
        element.box?.frame.x += 0.1

        f.coordinator.updateElement(.text(element), slideID: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.stored(f.s1.id)?.overrides, [.box])
        XCTAssertEqual(f.drawn(f.s1.id)?.box, element.box)
        XCTAssertEqual(f.drawn(f.s1.id)?.style, Self.themeBody)
    }

    func testEditingWordsDoesNotCountAsFormatting() throws {
        let f = themed()

        f.coordinator.updateSlideText("Uno", slideID: f.s1.id, inPresentation: f.presentationID)
        // The editor writes back the themed element it drew, with new words.
        var drawn = try XCTUnwrap(f.drawn(f.s1.id))
        drawn.text = "Una"
        f.coordinator.updateElement(.text(drawn), slideID: f.s1.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.stored(f.s1.id)?.overrides, [])
        XCTAssertEqual(f.drawn(f.s1.id)?.text, "Una")
    }

    func testApplyToAllSlidesCopiesTheLookAsDrawn() {
        // s1 follows the theme, but its stored style is still the plain default: it copies the theme's look.
        let following = themed()
        following.coordinator.applyTextFormatToAllSlides(from: following.s1.id, inPresentation: following.presentationID)
        XCTAssertEqual(following.drawn(following.s2.id)?.style, Self.themeBody)
        XCTAssertEqual(following.drawn(following.s2.id)?.box, Self.themeBox)

        // Formatted by hand, the copies are formatted by hand too, so later theme changes leave them alone.
        let formatted = themed()
        var style = Self.themeBody
        style.color = .black
        formatted.coordinator.setTextStyle(style, slideID: formatted.s1.id, inPresentation: formatted.presentationID)
        formatted.coordinator.applyTextFormatToAllSlides(from: formatted.s1.id, inPresentation: formatted.presentationID)
        XCTAssertEqual(formatted.drawn(formatted.s2.id)?.style, style)
        XCTAssertEqual(formatted.stored(formatted.s2.id)?.overrides, [.style, .box])
    }

    func testRevertToThemeFollowsTheThemeAgain() {
        let f = themed()
        f.coordinator.setTextStyle(TextStyle(fontSize: 30), slideID: f.s1.id, inPresentation: f.presentationID)
        f.coordinator.setTextStyle(TextStyle(fontSize: 31), slideID: f.s2.id, inPresentation: f.presentationID)

        XCTAssertEqual(f.coordinator.revertToTheme(elementID: f.stored(f.s1.id)?.id, inPresentation: f.presentationID), .applied)
        XCTAssertEqual(f.drawn(f.s1.id)?.style, Self.themeBody)
        XCTAssertEqual(f.drawn(f.s2.id)?.style.fontSize, 31)

        f.coordinator.revertToTheme(elementID: nil, inPresentation: f.presentationID)
        XCTAssertEqual(f.drawn(f.s2.id)?.style, .default(for: .title))
    }

    func testUpdateThemeFromTextRestylesEveryFollower() throws {
        let f = themed()
        f.coordinator.addSlide(toItem: f.item.id)
        var style = Self.themeBody
        style.color = .black
        f.coordinator.setTextStyle(style, slideID: f.s1.id, inPresentation: f.presentationID)
        let elementID = try XCTUnwrap(f.stored(f.s1.id)?.id)

        XCTAssertEqual(f.coordinator.updateThemeFromText(elementID, slideID: f.s1.id, inPresentation: f.presentationID), .applied)

        XCTAssertEqual(f.coordinator.project.theme(withID: f.theme.id)?.body.style, style)
        XCTAssertEqual(f.stored(f.s1.id)?.overrides, [])
        let added = try XCTUnwrap(f.presentation.slides.last)
        XCTAssertEqual(f.drawn(added.id)?.style, style, "a new blank slide follows the updated theme")
    }

    // MARK: Applying and removing

    func testApplyingAThemeCanKeepOrReplaceFormatting() {
        for keep in [true, false] {
            let f = makeFixture()
            let own = TextStyle(fontSize: 30)
            f.coordinator.setTextStyle(own, slideID: f.s1.id, inPresentation: f.presentationID)
            XCTAssertTrue(f.coordinator.hasOwnFormatting(f.presentationID))

            f.coordinator.setPresentationTheme(f.theme.id, presentationID: f.presentationID, keepSlideFormatting: keep)

            XCTAssertEqual(f.drawn(f.s1.id)?.style, keep ? own : Self.themeBody)
            XCTAssertEqual(f.drawn(f.s1.id)?.box, Self.themeBox, "the position wasn't set by hand")
            XCTAssertFalse(f.coordinator.hasOwnFormatting(f.presentationID), "it follows a theme now")
        }
    }

    func testRemovingOrDeletingAThemeKeepsTheLook() {
        for delete in [false, true] {
            let f = themed()
            let before = f.coordinator.project.renderedSlide(at: f.position1)

            if delete {
                XCTAssertEqual(f.coordinator.deleteTheme(f.theme.id), .applied)
                XCTAssertNil(f.coordinator.project.theme(withID: f.theme.id))
            } else {
                XCTAssertEqual(f.coordinator.setPresentationTheme(nil, presentationID: f.presentationID), .applied)
            }

            XCTAssertNil(f.presentation.themeID)
            XCTAssertEqual(f.coordinator.project.renderedSlide(at: f.position1), before)
            XCTAssertEqual(f.stored(f.s1.id)?.overrides, [])
        }
    }

    func testNewPresentationsFollowTheDefaultTheme() {
        let f = makeFixture()
        f.coordinator.setDefaultTheme(f.theme.id)
        XCTAssertEqual(f.coordinator.defaultThemeID, f.theme.id)

        let item = f.coordinator.addPresentation(title: "New")
        XCTAssertEqual(f.coordinator.project.presentation(forItem: item.id)?.themeID, f.theme.id)

        f.coordinator.deleteTheme(f.theme.id)
        XCTAssertNil(f.coordinator.project.defaultThemeID)
        let next = f.coordinator.addPresentation(title: "Next")
        XCTAssertNil(f.coordinator.project.presentation(forItem: next.id)?.themeID)
    }

    func testSongsFollowTheThemeChosenForThem() throws {
        let f = makeFixture()
        f.coordinator.setDefaultTheme(f.theme.id)

        let themed = try XCTUnwrap(f.coordinator.addSong(title: "S", lyrics: "Line one", themeID: f.theme.id))
        let plain = try XCTUnwrap(f.coordinator.addSong(title: "T", lyrics: "Line two", themeID: nil))
        let ghost = try XCTUnwrap(f.coordinator.addSong(title: "U", lyrics: "Line three", themeID: UUID()))

        XCTAssertEqual(f.coordinator.project.presentation(forItem: themed.id)?.themeID, f.theme.id)
        XCTAssertNil(f.coordinator.project.presentation(forItem: plain.id)?.themeID, "None, even with a default")
        XCTAssertNil(f.coordinator.project.presentation(forItem: ghost.id)?.themeID)
    }

    func testUnknownThemesAreRejected() {
        let f = makeFixture()
        XCTAssertEqual(f.coordinator.setPresentationTheme(UUID(), presentationID: f.presentationID), .rejected(.unknownTheme))
        XCTAssertEqual(f.coordinator.updateTheme(Theme(name: "Ghost")), .rejected(.unknownTheme))
        XCTAssertEqual(f.coordinator.deleteTheme(UUID()), .rejected(.unknownTheme))
        XCTAssertEqual(f.coordinator.revertToTheme(elementID: nil, inPresentation: f.presentationID), .rejected(.unknownTheme))
        var withMissingImage = f.theme
        withMissingImage.background = .image(ImageBackground(assetID: UUID()))
        XCTAssertEqual(f.coordinator.updateTheme(withMissingImage), .rejected(.unknownMediaAsset))
    }

    // MARK: Live output and undo

    func testEditingTheThemeMarksTheLiveSlideEditedButLeavesTheOutput() {
        let f = themed()
        f.coordinator.takeLive(slideID: f.s1.id, inItem: f.item.id)
        let live = f.coordinator.state.live

        var theme = f.theme
        theme.body.style.fontSize = 50
        f.coordinator.updateTheme(theme)

        XCTAssertEqual(f.coordinator.state.live, live)
        XCTAssertTrue(f.coordinator.liveSlideHasPendingEdits)
    }

    func testThemeEditsUndo() {
        let f = themed()
        var theme = f.theme
        theme.name = "Renamed"
        f.coordinator.updateTheme(theme)
        f.coordinator.setPresentationTheme(nil, presentationID: f.presentationID)

        f.coordinator.undo()
        XCTAssertEqual(f.presentation.themeID, f.theme.id)
        f.coordinator.undo()
        XCTAssertEqual(f.coordinator.project.theme(withID: f.theme.id)?.name, "Test")
    }

    // MARK: Saved data

    func testThemesAndTextEffectsRoundTripThroughJSON() throws {
        var f = themed().coordinator.project
        f.presentations[0].slides[0].elements = [.text(TextElement(
            text: "Hi",
            style: TextStyle(outline: TextOutline(color: .black, width: 6),
                             backgroundBox: TextBackgroundBox(padding: 30, cornerRadius: 8)),
            overrides: [.style]
        ))]
        f.defaultThemeID = f.themes[0].id

        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONEncoder().encode(f))

        XCTAssertEqual(decoded, f)
    }

    /// A version 2 project (betas 3 and 4) gets the starting themes; its presentations follow none and its text
    /// has no effects or overrides, so it draws exactly as before.
    func testVersionTwoProjectLoadsWithoutThemes() throws {
        let json = """
        {
          "id": "8E4B1C2A-0000-4000-8000-000000000001",
          "name": "Beta 4",
          "schemaVersion": 2,
          "presentations": [{
            "id": "8E4B1C2A-0000-4000-8000-000000000002",
            "title": "Song",
            "createdAt": 0,
            "updatedAt": 0,
            "slides": [{
              "id": "8E4B1C2A-0000-4000-8000-000000000003",
              "elements": [{"text": {"_0": {
                "id": "8E4B1C2A-0000-4000-8000-000000000004", "text": "Hi", "role": "body",
                "style": {"fontSize": 80, "weight": "bold", "isItalic": false, "alignment": "center",
                          "lineSpacing": 0, "hasShadow": true, "color": {"red": 1, "green": 1, "blue": 1, "alpha": 1}}
              }}}]
            }]
          }],
          "playlist": {"id": "8E4B1C2A-0000-4000-8000-000000000005", "title": "S", "items": []}
        }
        """

        let project = try JSONDecoder().decode(ProjectDocument.self, from: Data(json.utf8))

        XCTAssertEqual(project.themes.map(\.name), Theme.presets().map(\.name))
        XCTAssertNil(project.defaultThemeID)
        let presentation = try XCTUnwrap(project.presentations.first)
        XCTAssertNil(presentation.themeID)
        let element = try XCTUnwrap(presentation.slides.first?.primaryTextElement)
        XCTAssertEqual(element.overrides, [])
        XCTAssertNil(element.style.outline)
        XCTAssertNil(element.style.backgroundBox)
        XCTAssertEqual(project.rendered(presentation.slides[0], in: presentation).slide, presentation.slides[0])
    }

    func testTheLowerThirdPutsTitlesInTheBandToo() throws {
        let theme = try XCTUnwrap(Theme.presets().first { $0.name == "Lower Third" })
        XCTAssertEqual(theme.title.box, theme.body.box, "A title sits in the bottom band, not mid-screen")
        XCTAssertNotNil(theme.title.style.backgroundBox)
    }
}
