import Foundation

/// An sRGB colour with components in 0...1. Kept UI-free; the app converts it to SwiftUI/AppKit colours.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
}

public enum FontWeightValue: String, Codable, Hashable, Sendable, CaseIterable {
    case regular
    case medium
    case semibold
    case bold
    case heavy
}

public enum HorizontalTextAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case leading
    case center
    case trailing
}

public enum VerticalTextAlignment: String, Codable, Hashable, Sendable, CaseIterable {
    case top
    case center
    case bottom
}

/// How a text element looks. Sizes are in points on the 1920×1080 slide canvas.
public struct TextStyle: Codable, Hashable, Sendable {
    /// A font family name, or nil for the system font. A family that isn't installed falls back to the system font.
    public var fontFamily: String?
    public var fontSize: Double
    public var weight: FontWeightValue
    public var isItalic: Bool
    public var color: RGBAColor
    public var alignment: HorizontalTextAlignment
    public var lineSpacing: Double
    public var hasShadow: Bool

    public init(
        fontFamily: String? = nil,
        fontSize: Double = 96,
        weight: FontWeightValue = .semibold,
        isItalic: Bool = false,
        color: RGBAColor = .white,
        alignment: HorizontalTextAlignment = .center,
        lineSpacing: Double = 0,
        hasShadow: Bool = true
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.weight = weight
        self.isItalic = isItalic
        self.color = color
        self.alignment = alignment
        self.lineSpacing = lineSpacing
        self.hasShadow = hasShadow
    }

    /// The look each role had before styling existed, so unstyled slides render unchanged.
    public static func `default`(for role: TextRole) -> TextStyle {
        switch role {
        case .title: TextStyle(fontSize: 140, weight: .bold)
        case .body: TextStyle(fontSize: 96, weight: .semibold)
        case .caption: TextStyle(fontSize: 56, weight: .regular)
        }
    }
}

/// A rectangle in unit coordinates (0...1) of the slide canvas, independent of output resolution.
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The nine anchor points offered by the inspector's position control.
public enum BoxAnchor: String, Codable, Hashable, Sendable, CaseIterable {
    case topLeading, top, topTrailing
    case leading, center, trailing
    case bottomLeading, bottom, bottomTrailing

    public var horizontal: HorizontalTextAlignment {
        switch self {
        case .topLeading, .leading, .bottomLeading: .leading
        case .top, .center, .bottom: .center
        case .topTrailing, .trailing, .bottomTrailing: .trailing
        }
    }

    public var vertical: VerticalTextAlignment {
        switch self {
        case .topLeading, .top, .topTrailing: .top
        case .leading, .center, .trailing: .center
        case .bottomLeading, .bottom, .bottomTrailing: .bottom
        }
    }
}

/// Where a text element sits on the canvas. Text is aligned vertically inside the frame and
/// horizontally by its style's alignment.
public struct TextBox: Codable, Hashable, Sendable {
    public var frame: NormalizedRect
    public var verticalAlignment: VerticalTextAlignment

    public init(frame: NormalizedRect, verticalAlignment: VerticalTextAlignment = .center) {
        self.frame = frame
        self.verticalAlignment = verticalAlignment
    }

    /// A box covering the canvas inside `margin` (a fraction of the canvas height, applied on every side),
    /// with text pinned to `anchor`.
    public static func preset(_ anchor: BoxAnchor, margin: Double = 0.1) -> TextBox {
        // Same margin in points on both axes: the canvas is 16:9.
        let horizontal = margin * 9 / 16
        return TextBox(
            frame: NormalizedRect(x: horizontal, y: margin, width: 1 - 2 * horizontal, height: 1 - 2 * margin),
            verticalAlignment: anchor.vertical
        )
    }
}
