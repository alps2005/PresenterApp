import AppKit
import SwiftUI
import PresenterCore

/// Font, size, colour, shadow and alignment controls for one text style. Quick Edit lays them out in a
/// short, wide grid; the slide editor's inspector stacks them in a narrow column with line spacing too.
struct TextStyleControls: View {
    enum Layout {
        case wide
        case narrow
    }

    @Binding var style: TextStyle
    var layout: Layout = .wide

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    static let sizeRange: ClosedRange<Double> = 12...400
    private static let lineSpacingRange: ClosedRange<Double> = 0...80

    var body: some View {
        switch layout {
        case .wide:
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Font").foregroundStyle(.secondary)
                    HStack {
                        fontPicker.frame(width: 170)
                        weightPicker
                        italicToggle
                    }
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    HStack {
                        sizeField
                        colorPicker
                        shadowToggle
                    }
                }
                GridRow {
                    Text("Align").foregroundStyle(.secondary)
                    alignmentPicker
                }
            }
        case .narrow:
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Font").foregroundStyle(.secondary)
                    fontPicker
                }
                GridRow {
                    Text("Weight").foregroundStyle(.secondary)
                    HStack {
                        weightPicker
                        italicToggle
                    }
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    sizeField
                }
                GridRow {
                    Text("Color").foregroundStyle(.secondary)
                    HStack {
                        colorPicker
                        shadowToggle
                    }
                }
                GridRow {
                    Text("Align").foregroundStyle(.secondary)
                    alignmentPicker
                }
                GridRow {
                    Text("Spacing").foregroundStyle(.secondary)
                    HStack {
                        Slider(value: $style.lineSpacing, in: Self.lineSpacingRange)
                        Text("\(Int(style.lineSpacing))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                    .help("Extra space between lines, in slide points")
                }
            }
        }
    }

    private var fontPicker: some View {
        Picker("Font", selection: $style.fontFamily) {
            Text("System").tag(String?.none)
            Divider()
            // Keep a family that isn't installed selectable, so the picker shows what the slide asks for.
            if let family = style.fontFamily, !Self.fontFamilies.contains(family) {
                Text("\(family) (missing)").tag(Optional(family))
            }
            ForEach(Self.fontFamilies, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .labelsHidden()
    }

    private var weightPicker: some View {
        Picker("Weight", selection: $style.weight) {
            ForEach(FontWeightValue.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var italicToggle: some View {
        Toggle(isOn: $style.isItalic) { Image(systemName: "italic") }
            .toggleStyle(.button)
            .help("Italic")
    }

    private var sizeField: some View {
        HStack(spacing: 4) {
            TextField("Size", value: sizeBinding, format: .number.precision(.fractionLength(0)))
                .frame(width: 56)
                .labelsHidden()
            Stepper("Size", value: sizeBinding, in: Self.sizeRange, step: 4)
                .labelsHidden()
        }
    }

    private var colorPicker: some View {
        ColorPicker("Color", selection: Binding(
            get: { style.color.color },
            set: { style.color = RGBAColor($0) }
        ), supportsOpacity: true)
        .labelsHidden()
        .help("Text colour")
    }

    private var shadowToggle: some View {
        Toggle("Shadow", isOn: $style.hasShadow)
    }

    private var alignmentPicker: some View {
        Picker("Alignment", selection: $style.alignment) {
            Image(systemName: "text.alignleft").tag(HorizontalTextAlignment.leading)
            Image(systemName: "text.aligncenter").tag(HorizontalTextAlignment.center)
            Image(systemName: "text.alignright").tag(HorizontalTextAlignment.trailing)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { style.fontSize },
            set: { style.fontSize = min(max($0, Self.sizeRange.lowerBound), Self.sizeRange.upperBound) }
        )
    }
}
