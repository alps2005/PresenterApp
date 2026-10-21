import Foundation
import XCTest
@testable import PresenterCore

final class OutputLookTests: XCTestCase {
    private let background = SlideBackground.color(RGBAColor(red: 0.1, green: 0.2, blue: 0.3))
    private let green = RGBAColor(red: 0, green: 1, blue: 0)

    private func liveScene(_ text: String = "Amazing grace") -> AudienceScene {
        .slide(RenderedSlide(slide: .text(text), background: background))
    }

    func testEverythingShowsTheSceneUnchanged() {
        let look = OutputLook.everything
        XCTAssertTrue(look.isEverything)
        for scene in [AudienceScene.black, .empty, .background(background), liveScene()] {
            XCTAssertEqual(look.scene(from: scene, theme: nil), scene)
        }
    }

    func testAHiddenBackgroundBecomesTheKeyColourOrBlack() {
        var look = OutputLook(showsBackground: false)
        XCTAssertEqual(look.scene(from: .background(background), theme: nil), .background(.color(.black)))
        XCTAssertEqual(look.scene(from: .empty, theme: nil), .background(.color(.black)))
        look.keyColor = green
        let words = SlideDocument.text("Amazing grace")
        let scene = look.scene(from: .slide(RenderedSlide(slide: words, background: background)), theme: nil)
        XCTAssertEqual(scene, .slide(RenderedSlide(slide: words, background: .color(green))), "The words stay")
    }

    func testAHiddenSlideLeavesTheBackground() {
        let look = OutputLook(showsSlide: false)
        XCTAssertEqual(look.scene(from: liveScene(), theme: nil), .background(background))
        XCTAssertEqual(look.scene(from: .slide(RenderedSlide(slide: .text("a"))), theme: nil), .empty,
                       "With the default background, nothing but it")
    }

    func testBlackoutIsBlackOnEveryLook() {
        let look = OutputLook(showsBackground: false, showsSlide: false, keyColor: green)
        XCTAssertEqual(look.scene(from: .black, theme: nil), .black)
    }

    func testTheThemeRestylesTheWords() throws {
        var theme = try XCTUnwrap(Theme.presets().first)
        theme.body.style.fontSize = 33
        let look = OutputLook(themeID: theme.id)
        guard case .slide(let rendered) = look.scene(from: liveScene(), theme: theme) else { return XCTFail("slide expected") }
        guard case .text(let element) = rendered.slide.elements.first else { return XCTFail("text expected") }
        XCTAssertEqual(element.style.fontSize, 33)
    }

    func testAnOlderSavedLookDecodesWithDefaults() throws {
        let look = try JSONDecoder().decode(OutputLook.self, from: Data(#"{"showsProps":false}"#.utf8))
        XCTAssertEqual(look, OutputLook(showsProps: false))
    }

    func testTheSecondOutputHasItsOwnChannel() {
        var planner = OutputPlanner(displays: [])
        XCTAssertTrue(planner.show(.windowed, for: .secondAudience))
        XCTAssertTrue(planner.isEnabled(.secondAudience))
        XCTAssertFalse(planner.isEnabled(.audience))
        XCTAssertEqual(planner.status(.secondAudience), .windowed)
        XCTAssertTrue(OutputRole.secondAudience.isAudience)
        XCTAssertFalse(OutputRole.stage.isAudience)
    }
}
