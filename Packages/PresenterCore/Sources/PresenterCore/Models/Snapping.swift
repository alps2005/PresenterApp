import Foundation

/// Alignment guides for the slide editor, like Keynote's: while an element is dragged or resized, it snaps to
/// the slide's edges and centre and to other elements' edges and centres when it comes within a tolerance,
/// and the lines it lines up with are reported so the editor can draw them.
/// All values are unit coordinates of the slide canvas (0...1).
public enum Snapping {
    public struct Result: Equatable, Sendable {
        public var frame: NormalizedRect
        /// x positions of vertical guide lines to draw.
        public var verticalGuides: [Double]
        /// y positions of horizontal guide lines to draw.
        public var horizontalGuides: [Double]
    }

    /// Which edges a resize moves. Snapping only adjusts those.
    public struct Edges: Equatable, Sendable {
        public var left: Bool
        public var right: Bool
        public var top: Bool
        public var bottom: Bool

        public init(left: Bool = false, right: Bool = false, top: Bool = false, bottom: Bool = false) {
            self.left = left
            self.right = right
            self.top = top
            self.bottom = bottom
        }
    }

    /// Two lines closer than this count as the same line when deciding which guides to draw.
    private static let sameLine = 1e-6

    /// Moves `frame` the shortest distance (within `tolerance` on each axis) that lines up its left edge,
    /// centre or right edge, and its top, middle or bottom, with the slide or another element.
    public static func move(_ frame: NormalizedRect, among others: [NormalizedRect], tolerance: (x: Double, y: Double)) -> Result {
        let xLines = verticalLines(others)
        let yLines = horizontalLines(others)
        var snapped = frame
        if let dx = nearestOffset(from: [frame.minX, frame.midX, frame.maxX], to: xLines, within: tolerance.x) {
            snapped.x += dx
        }
        if let dy = nearestOffset(from: [frame.minY, frame.midY, frame.maxY], to: yLines, within: tolerance.y) {
            snapped.y += dy
        }
        return Result(
            frame: snapped,
            verticalGuides: matches(of: [snapped.minX, snapped.midX, snapped.maxX], in: xLines),
            horizontalGuides: matches(of: [snapped.minY, snapped.midY, snapped.maxY], in: yLines)
        )
    }

    /// Snaps the edges a resize is moving to the nearest line within `tolerance`, never shrinking the frame
    /// below `minimumSize`. Edges that aren't moving stay put.
    public static func resize(
        _ frame: NormalizedRect,
        moving edges: Edges,
        among others: [NormalizedRect],
        tolerance: (x: Double, y: Double),
        minimumSize: Double = 0.02
    ) -> Result {
        let xLines = verticalLines(others)
        let yLines = horizontalLines(others)
        var left = frame.minX, right = frame.maxX, top = frame.minY, bottom = frame.maxY
        if edges.left, let dx = nearestOffset(from: [left], to: xLines, within: tolerance.x), right - (left + dx) >= minimumSize {
            left += dx
        }
        if edges.right, let dx = nearestOffset(from: [right], to: xLines, within: tolerance.x), (right + dx) - left >= minimumSize {
            right += dx
        }
        if edges.top, let dy = nearestOffset(from: [top], to: yLines, within: tolerance.y), bottom - (top + dy) >= minimumSize {
            top += dy
        }
        if edges.bottom, let dy = nearestOffset(from: [bottom], to: yLines, within: tolerance.y), (bottom + dy) - top >= minimumSize {
            bottom += dy
        }
        // Rebuilding from edges adds floating-point noise, so keep the original when nothing snapped.
        let didSnap = left != frame.minX || right != frame.maxX || top != frame.minY || bottom != frame.maxY
        let snapped = didSnap ? NormalizedRect(x: left, y: top, width: right - left, height: bottom - top) : frame
        let movingX = (edges.left ? [left] : []) + (edges.right ? [right] : [])
        let movingY = (edges.top ? [top] : []) + (edges.bottom ? [bottom] : [])
        return Result(
            frame: snapped,
            verticalGuides: matches(of: movingX, in: xLines),
            horizontalGuides: matches(of: movingY, in: yLines)
        )
    }

    // MARK: Lines

    private static func verticalLines(_ others: [NormalizedRect]) -> [Double] {
        [0, 0.5, 1] + others.flatMap { [$0.minX, $0.midX, $0.maxX] }
    }

    private static func horizontalLines(_ others: [NormalizedRect]) -> [Double] {
        [0, 0.5, 1] + others.flatMap { [$0.minY, $0.midY, $0.maxY] }
    }

    /// The smallest shift (within `tolerance`) that puts one of `points` exactly on one of `lines`.
    private static func nearestOffset(from points: [Double], to lines: [Double], within tolerance: Double) -> Double? {
        var best: Double?
        for point in points {
            for line in lines {
                let offset = line - point
                if abs(offset) <= tolerance, abs(offset) < abs(best ?? .infinity) {
                    best = offset
                }
            }
        }
        return best
    }

    /// The lines that `points` sit on, without duplicates.
    private static func matches(of points: [Double], in lines: [Double]) -> [Double] {
        var result: [Double] = []
        for line in lines where points.contains(where: { abs($0 - line) < sameLine }) {
            if !result.contains(where: { abs($0 - line) < sameLine }) { result.append(line) }
        }
        return result.sorted()
    }
}

extension Snapping {
    /// `origin` with the `moving` edges dragged by (`dx`, `dy`), before snapping. Each moving edge stays on the
    /// canvas and at least `minimumSize` from the opposite edge; the other edges stay put.
    public static func resized(
        _ origin: NormalizedRect, moving edges: Edges, by dx: Double, _ dy: Double, minimumSize: Double
    ) -> NormalizedRect {
        var left = origin.minX, right = origin.maxX
        var top = origin.minY, bottom = origin.maxY
        if edges.left { left = min(max(left + dx, 0), right - minimumSize) }
        if edges.right { right = max(min(right + dx, 1), left + minimumSize) }
        if edges.top { top = min(max(top + dy, 0), bottom - minimumSize) }
        if edges.bottom { bottom = max(min(bottom + dy, 1), top + minimumSize) }
        return NormalizedRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

extension SlideElement {
    /// A copy with a new identity for pasting. Like Keynote, a copy that would land exactly on an element
    /// already on the slide is nudged down and to the right by `offset`, up to `maxNudges` times.
    public func pastedCopy(
        avoiding occupied: [NormalizedRect], offset: (dx: Double, dy: Double), maxNudges: Int = 20
    ) -> SlideElement {
        var copy = duplicated()
        var nudges = 0
        while let frame = copy.frame, nudges < maxNudges, occupied.contains(where: { $0.isClose(to: frame) }) {
            copy = copy.duplicated(offsetBy: offset.dx, offset.dy)
            nudges += 1
        }
        return copy
    }
}

extension NormalizedRect {
    public var minX: Double { x }
    public var midX: Double { x + width / 2 }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var midY: Double { y + height / 2 }
    public var maxY: Double { y + height }

    /// The same frame, allowing for floating-point error.
    public func isClose(to other: NormalizedRect) -> Bool {
        abs(x - other.x) < 1e-6 && abs(y - other.y) < 1e-6 && abs(width - other.width) < 1e-6 && abs(height - other.height) < 1e-6
    }
}
