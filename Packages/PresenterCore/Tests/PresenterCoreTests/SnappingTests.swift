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
}
