import AppKit
import SwiftUI
import PresenterCore

extension RGBAColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}

extension TextStyle {
    /// The font family if it's installed, else the system font, so a project from another Mac still renders.
    var font: Font {
        var font: Font
        if let fontFamily, NSFontManager.shared.availableFontFamilies.contains(fontFamily) {
            font = .custom(fontFamily, fixedSize: fontSize)
        } else {
            font = .system(size: fontSize)
        }
        font = font.weight(weight.fontWeight)
        return isItalic ? font.italic() : font
    }
}

extension FontWeightValue {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    var label: String { rawValue.capitalized }
}

extension HorizontalTextAlignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

extension VerticalTextAlignment {
    var verticalAlignment: VerticalAlignment {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}
