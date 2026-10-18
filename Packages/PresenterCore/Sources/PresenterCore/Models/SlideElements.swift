import Foundation

/// A filled and/or outlined shape placed on the slide canvas.
public struct ShapeElement: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case rectangle
        case roundedRectangle
        case ellipse
    }

    public let id: UUID
    public var kind: Kind
    public var frame: NormalizedRect
    /// Nil draws no fill.
    public var fill: RGBAColor?
    /// Nil draws no outline.
    public var stroke: RGBAColor?
    /// Outline width in points on the 1920×1080 canvas.
    public var strokeWidth: Double
    /// Corner radius in canvas points. Only rounded rectangles use it.
    public var cornerRadius: Double
    /// Its own transitions as the slide arrives and leaves. Nil follows the slide.
    public var transitionIn: ElementTransition?
    public var transitionOut: ElementTransition?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        frame: NormalizedRect,
        fill: RGBAColor? = RGBAColor(red: 0.2, green: 0.45, blue: 0.85),
        stroke: RGBAColor? = nil,
        strokeWidth: Double = 6,
        cornerRadius: Double = 32,
        transitionIn: ElementTransition? = nil,
        transitionOut: ElementTransition? = nil
    ) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
    }
}

/// An image from the media library placed on the slide canvas.
public struct ImageElement: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var assetID: UUID
    public var frame: NormalizedRect
    public var scaling: ImageScaling
    /// 0...1.
    public var opacity: Double
    /// Its own transitions as the slide arrives and leaves. Nil follows the slide.
    public var transitionIn: ElementTransition?
    public var transitionOut: ElementTransition?

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        frame: NormalizedRect,
        scaling: ImageScaling = .fit,
        opacity: Double = 1,
        transitionIn: ElementTransition? = nil,
        transitionOut: ElementTransition? = nil
    ) {
        self.id = id
        self.assetID = assetID
        self.frame = frame
        self.scaling = scaling
        self.opacity = opacity
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
    }
}

/// How the audience output changes to a slide when it goes live. A slide without one cuts instantly.
public enum SlideTransition: Codable, Hashable, Sendable {
    /// Cross-fades from the previous slide over `duration` seconds.
    case dissolve(duration: Double)
    /// The previous slide fades out to black, then this one fades in.
    case fadeThroughBlack(duration: Double)
    /// Slides in from `edge`, pushing the previous slide out the other side.
    case push(edge: TransitionEdge, duration: Double)
    /// Revealed over the previous slide by a line sweeping in from `edge`.
    case wipe(edge: TransitionEdge, duration: Double)
    /// Grows in from slightly smaller while fading in.
    case zoom(duration: Double)

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case dissolve, fadeThroughBlack, push, wipe, zoom

        /// Push and Wipe come in from a side.
        public var hasEdge: Bool { self == .push || self == .wipe }
    }

    public static let durationRange: ClosedRange<Double> = 0.2...2

    public init(kind: Kind, edge: TransitionEdge = .left, duration: Double) {
        switch kind {
        case .dissolve: self = .dissolve(duration: duration)
        case .fadeThroughBlack: self = .fadeThroughBlack(duration: duration)
        case .push: self = .push(edge: edge, duration: duration)
        case .wipe: self = .wipe(edge: edge, duration: duration)
        case .zoom: self = .zoom(duration: duration)
        }
    }

    public var kind: Kind {
        switch self {
        case .dissolve: .dissolve
        case .fadeThroughBlack: .fadeThroughBlack
        case .push: .push
        case .wipe: .wipe
        case .zoom: .zoom
        }
    }

    /// The side a Push or Wipe comes in from. Nil for the others.
    public var edge: TransitionEdge? {
        switch self {
        case .push(let edge, _), .wipe(let edge, _): edge
        case .dissolve, .fadeThroughBlack, .zoom: nil
        }
    }

    public var duration: Double {
        switch self {
        case .dissolve(let duration), .fadeThroughBlack(let duration), .zoom(let duration): duration
        case .push(_, let duration), .wipe(_, let duration): duration
        }
    }

    /// The same transition with another kind, side or duration.
    public func with(kind: Kind? = nil, edge: TransitionEdge? = nil, duration: Double? = nil) -> SlideTransition {
        SlideTransition(kind: kind ?? self.kind, edge: edge ?? self.edge ?? .left, duration: duration ?? self.duration)
    }
}

extension SlideElement {
    /// Where the element sits on the canvas. Text without a box uses the centred flow layout and has no frame;
    /// giving it one places it in a box.
    public var frame: NormalizedRect? {
        get {
            switch self {
            case .text(let text): text.box?.frame
            case .shape(let shape): shape.frame
            case .image(let image): image.frame
            }
        }
        set {
            guard let newValue else {
                if case .text(var text) = self {
                    text.box = nil
                    self = .text(text)
                }
                return
            }
            switch self {
            case .text(var text):
                text.box = TextBox(frame: newValue, verticalAlignment: text.box?.verticalAlignment ?? .center)
                self = .text(text)
            case .shape(var shape):
                shape.frame = newValue
                self = .shape(shape)
            case .image(var image):
                image.frame = newValue
                self = .image(image)
            }
        }
    }

    /// A copy with a new identity, moved by (`dx`, `dy`) in unit coordinates and kept on the canvas.
    /// Text without a box keeps flowing; it has no position to offset.
    public func duplicated(offsetBy dx: Double = 0, _ dy: Double = 0) -> SlideElement {
        var copy: SlideElement = switch self {
        case .text(let text):
            .text(TextElement(text: text.text, role: text.role, style: text.style, box: text.box, overrides: text.overrides))
        case .shape(let shape):
            .shape(ShapeElement(kind: shape.kind, frame: shape.frame, fill: shape.fill, stroke: shape.stroke,
                                strokeWidth: shape.strokeWidth, cornerRadius: shape.cornerRadius))
        case .image(let image):
            .image(ImageElement(assetID: image.assetID, frame: image.frame, scaling: image.scaling, opacity: image.opacity))
        }
        copy[transition: .in] = self[transition: .in]
        copy[transition: .out] = self[transition: .out]
        if var frame = copy.frame {
            frame.x += dx
            frame.y += dy
            copy.frame = frame.clampedToCanvas()
        }
        return copy
    }

    /// The element's own In or Out transition. Nil follows the slide.
    public subscript(transition phase: ElementPhase) -> ElementTransition? {
        get {
            switch (self, phase) {
            case (.text(let text), .in): text.transitionIn
            case (.text(let text), .out): text.transitionOut
            case (.shape(let shape), .in): shape.transitionIn
            case (.shape(let shape), .out): shape.transitionOut
            case (.image(let image), .in): image.transitionIn
            case (.image(let image), .out): image.transitionOut
            }
        }
        set {
            switch self {
            case .text(var text):
                if phase == .in { text.transitionIn = newValue } else { text.transitionOut = newValue }
                self = .text(text)
            case .shape(var shape):
                if phase == .in { shape.transitionIn = newValue } else { shape.transitionOut = newValue }
                self = .shape(shape)
            case .image(var image):
                if phase == .in { image.transitionIn = newValue } else { image.transitionOut = newValue }
                self = .image(image)
            }
        }
    }

    /// The media asset the element needs, if any.
    public var assetID: UUID? {
        if case .image(let image) = self { return image.assetID }
        return nil
    }
}

extension NormalizedRect {
    /// A rectangle of the given size (in unit coordinates) centred on the canvas.
    public static func centered(width: Double, height: Double) -> NormalizedRect {
        NormalizedRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// Moved and shrunk as needed so it lies inside the canvas, keeping at least `minimumSize` on each axis.
    public func clampedToCanvas(minimumSize: Double = 0.02) -> NormalizedRect {
        let width = min(max(self.width, minimumSize), 1)
        let height = min(max(self.height, minimumSize), 1)
        return NormalizedRect(
            x: min(max(x, 0), 1 - width),
            y: min(max(y, 0), 1 - height),
            width: width,
            height: height
        )
    }
}
