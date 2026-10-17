import AppKit
import SwiftUI
import PresenterCore

/// Font, size, colour, shadow, alignment and effects controls for one text style. Quick Edit lays them out in a
/// short, wide grid with effects in a popover; the slide editor's inspector stacks them in a narrow column with line
/// spacing too.
struct TextStyleControls: View {
    enum Layout {
        case wide
        case narrow
    }

    @Binding var style: TextStyle
    var layout: Layout = .wide
    @State private var isShowingEffects = false

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    static let sizeRange: ClosedRange<Double> = 12...400
    private static let lineSpacingRange: ClosedRange<Double> = 0...80

    var body: some View {
        switch layout {
        case .wide:
            Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
                GridRow {
                    Text("Font").foregroundStyle(.secondary)
                    HStack {
                        fontPicker
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
                        effectsButton
                    }
                }
                GridRow {
                    Text("Align").foregroundStyle(.secondary)
                    alignmentPicker
                }
            }
        case .narrow:
            Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
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
                effectRows
            }
        }
    }

    // MARK: Effects

    /// Quick Edit is too short for more rows, so its effects open in a popover.
    private var effectsButton: some View {
        Button("Effects…") { isShowingEffects = true }
            .help("Outline and background box")
            .popover(isPresented: $isShowingEffects, arrowEdge: .bottom) {
                Grid(alignment: .leading, horizontalSpacing: Spacing.md, verticalSpacing: Spacing.md) {
                    effectRows
                }
                .controlSize(.small)
                .padding(Spacing.lg)
                .frame(width: 300, alignment: .leading)
            }
    }

    @ViewBuilder
    private var effectRows: some View {
        GridRow {
            Text("Outline").foregroundStyle(.secondary)
            HStack {
                Toggle(isOn: Binding(
                    get: { style.outline != nil },
                    set: { style.outline = $0 ? TextOutline() : nil }
                )) { Text("Outline") }
                .labelsHidden()
                if let outline = style.outline {
                    ColorPicker("Outline colour", selection: Binding(
                        get: { outline.color.color },
                        set: { style.outline?.color = RGBAColor($0) }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    Slider(value: Binding(
                        get: { outline.width },
                        set: { style.outline?.width = $0 }
                    ), in: TextOutline.widthRange)
                    .frame(minWidth: Widths.compactSlider)
                    .accessibilityLabel("Outline width")
                    .help("Outline width")
                }
            }
        }
        GridRow {
            Text("Box").foregroundStyle(.secondary)
            HStack {
                Toggle(isOn: Binding(
                    get: { style.backgroundBox != nil },
                    set: { style.backgroundBox = $0 ? TextBackgroundBox() : nil }
                )) { Text("Background box") }
                .labelsHidden()
                .help("A filled box behind the words")
                if let box = style.backgroundBox {
                    ColorPicker("Box colour", selection: Binding(
                        get: { box.color.color },
                        set: { style.backgroundBox?.color = RGBAColor($0) }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    Slider(value: Binding(
                        get: { box.padding },
                        set: { style.backgroundBox?.padding = $0 }
                    ), in: TextBackgroundBox.paddingRange)
                    .frame(minWidth: Widths.compactSlider)
                    .accessibilityLabel("Space around the words")
                    .help("Space around the words")
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
        // A fixed width: a menu is otherwise as wide as the longest font name installed on this Mac.
        .frame(width: Widths.fontMenu)
    }

    private var weightPicker: some View {
        Picker("Weight", selection: $style.weight) {
            ForEach(FontWeightValue.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var italicToggle: some View {
        Toggle(isOn: $style.isItalic) { Image(systemName: "italic").accessibilityLabel("Italic") }
            .toggleStyle(.button)
            .help("Italic")
    }

    private var sizeField: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Size", value: sizeBinding, format: .number.precision(.fractionLength(0)))
                .frame(width: Widths.numberField)
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
            Image(systemName: "text.alignleft").accessibilityLabel("Align left").tag(HorizontalTextAlignment.leading)
            Image(systemName: "text.aligncenter").accessibilityLabel("Align centre").tag(HorizontalTextAlignment.center)
            Image(systemName: "text.alignright").accessibilityLabel("Align right").tag(HorizontalTextAlignment.trailing)
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
