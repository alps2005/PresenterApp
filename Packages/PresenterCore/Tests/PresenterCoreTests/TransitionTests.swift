import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class TransitionTests: XCTestCase {
    // MARK: Slide transitions

    func testEveryKindRoundTripsAndOldDissolvesStillLoad() throws {
        let transitions: [SlideTransition] = [
            .dissolve(duration: 0.8), .fadeThroughBlack(duration: 1), .push(edge: .right, duration: 0.5),
            .wipe(edge: .top, duration: 0.7), .zoom(duration: 0.4),
        ]
        for transition in transitions {
            let data = try JSONEncoder().encode(transition)
            XCTAssertEqual(try JSONDecoder().decode(SlideTransition.self, from: data), transition)
        }
        // How beta 8 and earlier saved a dissolve.
        let old = Data(#"{"dissolve":{"duration":0.6}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SlideTransition.self, from: old), .dissolve(duration: 0.6))
    }

    func testKindsEdgesAndDurations() {
        let push = SlideTransition.push(edge: .bottom, duration: 0.9)
        XCTAssertEqual(push.kind, .push)
        XCTAssertEqual(push.edge, .bottom)
        XCTAssertEqual(push.duration, 0.9)
        XCTAssertEqual(push.with(kind: .wipe), .wipe(edge: .bottom, duration: 0.9))
        XCTAssertEqual(push.with(kind: .zoom), .zoom(duration: 0.9))
        XCTAssertEqual(SlideTransition.zoom(duration: 0.5).with(kind: .push), .push(edge: .left, duration: 0.5))
        XCTAssertNil(SlideTransition.dissolve(duration: 1).edge)
        XCTAssertTrue(SlideTransition.Kind.wipe.hasEdge)
        XCTAssertFalse(SlideTransition.Kind.fadeThroughBlack.hasEdge)
    }

    func testSlideTransitionGeometry() {
        typealias M = TransitionMath
        // Dissolve: the incoming slide fades in over an unchanged outgoing one.
        XCTAssertEqual(M.frame(for: .dissolve(duration: 1), role: .incoming, progress: 0.25).opacity, 0.25)
        XCTAssertEqual(M.frame(for: .dissolve(duration: 1), role: .outgoing, progress: 0.25), .identity)
        // On the see-through slide layer the outgoing words fade out instead, so the two don't pile up.
        XCTAssertEqual(M.frame(for: .dissolve(duration: 1), role: .outgoing, progress: 0.25, opaque: false).opacity, 0.75)
        XCTAssertEqual(M.frame(for: .zoom(duration: 1), role: .outgoing, progress: 1, opaque: false).opacity, 0)
        XCTAssertEqual(M.frame(for: .wipe(edge: .left, duration: 1), role: .outgoing, progress: 0.3, opaque: false),
                       TransitionFrame(reveal: 0.7, revealEdge: .right), "Hidden where the incoming slide is revealed")
        XCTAssertEqual(M.frame(for: .wipe(edge: .left, duration: 1), role: .outgoing, progress: 0.3), .identity)
        // Fade Through Black is black halfway.
        let fade = SlideTransition.fadeThroughBlack(duration: 1)
        XCTAssertEqual(M.frame(for: fade, role: .outgoing, progress: 0.5).opacity, 0)
        XCTAssertEqual(M.frame(for: fade, role: .incoming, progress: 0.5).opacity, 0)
        XCTAssertEqual(M.frame(for: fade, role: .outgoing, progress: 0.25).opacity, 0.5)
        XCTAssertEqual(M.frame(for: fade, role: .incoming, progress: 1).opacity, 1)
        // Push from the left: in from off the left edge, the old slide out to the right.
        let push = SlideTransition.push(edge: .left, duration: 1)
        XCTAssertEqual(M.frame(for: push, role: .incoming, progress: 0).offsetX, -1)
        XCTAssertEqual(M.frame(for: push, role: .incoming, progress: 1).offsetX, 0)
        XCTAssertEqual(M.frame(for: push, role: .outgoing, progress: 0.5).offsetX, 0.5)
        XCTAssertEqual(M.frame(for: .push(edge: .top, duration: 1), role: .incoming, progress: 0.5).offsetY, -0.5)
        // Wipe reveals the incoming slide from its edge; Zoom grows it in.
        XCTAssertEqual(M.frame(for: .wipe(edge: .right, duration: 1), role: .incoming, progress: 0.4),
                       TransitionFrame(reveal: 0.4, revealEdge: .right))
        let zoom = M.frame(for: .zoom(duration: 1), role: .incoming, progress: 0)
        XCTAssertEqual(zoom.opacity, 0)
        XCTAssertEqual(zoom.scale, 0.85)
        XCTAssertEqual(M.frame(for: .zoom(duration: 1), role: .incoming, progress: 2), .identity, "Progress is clamped")
    }

    // MARK: Element transitions

    func testElementTransitionTiming() {
        let fadeIn = ElementTransition(kind: .fade, duration: 2, delay: 1)
        XCTAssertEqual(fadeIn.progress(elapsed: 0.5, phase: .in), 0, "Hidden until its delay")
        XCTAssertEqual(fadeIn.progress(elapsed: 2, phase: .in), 0.5)
        XCTAssertEqual(fadeIn.progress(elapsed: 9, phase: .in), 1)
        XCTAssertEqual(fadeIn.end(phase: .in), 3)
        XCTAssertEqual(fadeIn.progress(elapsed: 1, phase: .out), 0.5, "Out ignores the delay")
        XCTAssertEqual(fadeIn.end(phase: .out), 2)
    }

    func testElementTransitionGeometry() {
        typealias M = TransitionMath
        let fade = ElementTransition(kind: .fade)
        XCTAssertEqual(M.frame(for: fade, phase: .in, progress: 0.3).opacity, 0.3)
        XCTAssertEqual(M.frame(for: fade, phase: .out, progress: 0.3).opacity, 0.7)
        let push = ElementTransition(kind: .push, edge: .bottom)
        XCTAssertEqual(M.frame(for: push, phase: .in, progress: 0).offsetY, 1, "Starts a whole canvas below")
        XCTAssertEqual(M.frame(for: push, phase: .out, progress: 1).offsetY, 1, "Leaves through the bottom")
        XCTAssertEqual(M.frame(for: ElementTransition(kind: .wipe, edge: .top), phase: .in, progress: 0.5),
                       TransitionFrame(reveal: 0.5, revealEdge: .top))
        XCTAssertEqual(M.frame(for: ElementTransition(kind: .zoom), phase: .in, progress: 1), .identity)
    }

    func testSlidesKnowWhenTheirElementTransitionsEnd() {
        let title = TextElement(text: "Title", role: .title, transitionIn: ElementTransition(kind: .fade, duration: 0.5, delay: 1))
        let verse = TextElement(text: "Verse", transitionOut: ElementTransition(kind: .zoom, duration: 0.8))
        let slide = SlideDocument(elements: [.text(title), .text(verse), .shape(ShapeElement(kind: .ellipse, frame: .centered(width: 0.2, height: 0.2)))])
        XCTAssertTrue(slide.hasElementTransitions)
        XCTAssertEqual(slide.elementTransitionsEnd(.in), 1.5)
        XCTAssertEqual(slide.elementTransitionsEnd(.out), 0.8)
        XCTAssertFalse(SlideDocument.text("Plain").hasElementTransitions)
        XCTAssertEqual(SlideDocument.text("Plain").elementTransitionsEnd(.in), 0)
    }

    func testElementTransitionsRoundTripAndOldElementsLoadWithout() throws {
        let image = ImageElement(assetID: UUID(), frame: .centered(width: 0.5, height: 0.5),
                                 transitionIn: ElementTransition(kind: .wipe, edge: .right, duration: 1.2, delay: 0.5))
        let text = TextElement(text: "Hi", transitionOut: ElementTransition(kind: .push, edge: .top))
        let slide = SlideDocument(elements: [.image(image), .text(text)])
        XCTAssertEqual(try JSONDecoder().decode(SlideDocument.self, from: JSONEncoder().encode(slide)), slide)

        let oldText = Data(#"{"id":"8E4B1C2A-0000-4000-8000-000000000004","text":"Hi","role":"body"}"#.utf8)
        let decoded = try JSONDecoder().decode(TextElement.self, from: oldText)
        XCTAssertNil(decoded.transitionIn)
        XCTAssertNil(decoded.transitionOut)
    }

    func testSettingElementTransitionsIsUndoableClampedAndSurvivesDuplicate() throws {
        let text = TextElement(text: "Verse")
        let slide = SlideDocument(elements: [.text(text)])
        let presentation = PresentationDocument(title: "P", slides: [slide])
        let c = PresentationCoordinator(project: ProjectDocument(
            name: "T", presentations: [presentation],
            playlist: PlaylistDocument(title: "S", items: [PresentationItem(presentationID: presentation.id)])
        ))

        let fade = ElementTransition(kind: .fade, duration: 9, delay: -2)
        XCTAssertEqual(c.setElementTransition(fade, phase: .in, elementID: text.id, slideID: slide.id, inPresentation: presentation.id), .applied)
        let stored = try XCTUnwrap(c.project.presentations[0].slides[0].elements[0][transition: .in])
        XCTAssertEqual(stored.duration, ElementTransition.durationRange.upperBound)
        XCTAssertEqual(stored.delay, 0)
        XCTAssertNil(c.project.presentations[0].slides[0].elements[0][transition: .out])

        XCTAssertEqual(c.project.presentations[0].slides[0].elements[0].duplicated()[transition: .in], stored,
                       "A duplicate keeps the transitions")

        XCTAssertEqual(c.setElementTransition(fade, phase: .out, elementID: UUID(), slideID: slide.id, inPresentation: presentation.id),
                       .rejected(.unknownElement))
        c.undo()
        XCTAssertNil(c.project.presentations[0].slides[0].elements[0][transition: .in])
    }

    func testThemesLeaveElementTransitionsAlone() throws {
        let transition = ElementTransition(kind: .zoom, duration: 1)
        let slide = SlideDocument(elements: [.text(TextElement(text: "Hi", transitionIn: transition))])
        let themed = try XCTUnwrap(Theme.presets().first).applied(to: slide)
        XCTAssertEqual(themed.elements[0][transition: .in], transition)
    }
}
