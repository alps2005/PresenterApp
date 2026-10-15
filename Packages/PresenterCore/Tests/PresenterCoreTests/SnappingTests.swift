import XCTest
@testable import PresenterCore

final class SnappingTests: XCTestCase {
    private let tolerance = (x: 0.01, y: 0.01)

    func testCentreSnapsToSlideCentreWithinTolerance() {
        // Centre at (0.505, 0.493): both within 0.01 of the slide centre.
        let frame = NormalizedRect(x: 0.405, y: 0.393, width: 0.2, height: 0.2)

        let result = Snapping.move(frame, among: [], tolerance: tolerance)

        XCTAssertEqual(result.frame.midX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.frame.midY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.verticalGuides, [0.5])
        XCTAssertEqual(result.horizontalGuides, [0.5])
    }

    func testNothingSnapsOutsideTolerance() {
        let frame = NormalizedRect(x: 0.33, y: 0.21, width: 0.2, height: 0.2)

        let result = Snapping.move(frame, among: [], tolerance: tolerance)

        XCTAssertEqual(result.frame, frame)
        XCTAssertEqual(result.verticalGuides, [])
        XCTAssertEqual(result.horizontalGuides, [])
    }

    func testEdgesSnapToSlideEdges() {
        let frame = NormalizedRect(x: 0.006, y: 0.795, width: 0.2, height: 0.2)

        let result = Snapping.move(frame, among: [], tolerance: tolerance)

        XCTAssertEqual(result.frame.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(result.frame.maxY, 1, accuracy: 1e-9)
        XCTAssertEqual(result.verticalGuides, [0])
        XCTAssertEqual(result.horizontalGuides, [1])
    }

    func testAlignsWithAnotherElementsEdgeAndPicksTheNearestLine() {
        let other = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        // Left edge 0.104 is 0.004 from the other's left (0.1); nothing else is as close.
        let frame = NormalizedRect(x: 0.104, y: 0.6, width: 0.15, height: 0.15)

        let result = Snapping.move(frame, among: [other], tolerance: tolerance)

        XCTAssertEqual(result.frame.minX, 0.1, accuracy: 1e-9)
        XCTAssertEqual(result.verticalGuides, [0.1])
        XCTAssertEqual(result.frame.y, 0.6, accuracy: 1e-9)
    }

    func testResizeSnapsOnlyTheMovingEdge() {
        let frame = NormalizedRect(x: 0.2, y: 0.2, width: 0.296, height: 0.3)

        let result = Snapping.resize(frame, moving: Snapping.Edges(right: true), among: [], tolerance: tolerance)

        XCTAssertEqual(result.frame.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(result.frame.maxX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.verticalGuides, [0.5])
        XCTAssertEqual(result.horizontalGuides, [])
    }

    func testResizeNeverSnapsBelowMinimumSize() {
        // The right edge is near the centre line, but snapping it would leave a width under the minimum.
        let frame = NormalizedRect(x: 0.495, y: 0.2, width: 0.015, height: 0.3)

        let result = Snapping.resize(frame, moving: Snapping.Edges(right: true), among: [], tolerance: tolerance, minimumSize: 0.02)

        XCTAssertEqual(result.frame, frame)
    }

    // MARK: Resize clamping and paste placement

    func testResizeMovesOnlyTheDraggedEdges() {
        let origin = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let frame = Snapping.resized(origin, moving: Snapping.Edges(right: true, bottom: true), by: 0.1, 0.05, minimumSize: 0.02)
        XCTAssertEqual(frame.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(frame.maxX, 0.7, accuracy: 1e-9)
        XCTAssertEqual(frame.minY, 0.2, accuracy: 1e-9)
        XCTAssertEqual(frame.maxY, 0.65, accuracy: 1e-9)
    }

    func testResizeStaysOnTheCanvas() {
        let origin = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let frame = Snapping.resized(origin, moving: Snapping.Edges(left: true, top: true), by: -0.5, -0.5, minimumSize: 0.02)
        XCTAssertEqual(frame.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.maxX, 0.6, accuracy: 1e-9)
        XCTAssertEqual(frame.maxY, 0.6, accuracy: 1e-9)
    }

    func testResizePastTheOppositeEdgeStopsAtTheMinimumSize() {
        let origin = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let frame = Snapping.resized(origin, moving: Snapping.Edges(right: true), by: -0.9, 0, minimumSize: 0.05)
        XCTAssertEqual(frame.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(frame.width, 0.05, accuracy: 1e-9)
    }

    func testPastedCopyIsNudgedOffElementsItWouldCover() {
        let offset = (dx: 0.01, dy: 0.02)
        let frame = NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let element = SlideElement.shape(ShapeElement(kind: .rectangle, frame: frame))
        let once = NormalizedRect(x: 0.11, y: 0.12, width: 0.2, height: 0.2)

        let free = element.pastedCopy(avoiding: [], offset: offset)
        XCTAssertNotEqual(free.id, element.id)
        XCTAssertEqual(free.frame, frame)

        let nudged = element.pastedCopy(avoiding: [frame, once], offset: offset)
        XCTAssertEqual(nudged.frame?.x ?? 0, 0.12, accuracy: 1e-9)
        XCTAssertEqual(nudged.frame?.y ?? 0, 0.14, accuracy: 1e-9)
    }

    func testPastedCopyGivesUpAfterTheNudgeLimit() {
        let offset = (dx: 0.01, dy: 0.0)
        let frame = NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let occupied = (0..<50).map { NormalizedRect(x: Double($0) * 0.01, y: 0, width: 0.1, height: 0.1) }
        let copy = SlideElement.shape(ShapeElement(kind: .rectangle, frame: frame)).pastedCopy(avoiding: occupied, offset: offset, maxNudges: 3)
        XCTAssertEqual(copy.frame?.x ?? 0, 0.03, accuracy: 1e-9)
    }
}
