import AppKit
import Observation
import PresenterCore
import SwiftUI

/// How Presenter looks on this Mac: appearance, text size and the colours that mark state and song sections.
/// Kept in this Mac's preferences, not the project, so moving a project never changes anyone's screen.
///
/// Views read it through `AppSettings.shared` (`Palette.live`, `Font.ui(_:)`, `GroupLabelTag`); SwiftUI tracks those
/// reads, so a change in Settings redraws everything that uses it straight away.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)

    enum Appearance: String, CaseIterable, Identifiable {
        /// The console's own look: dark, for dark booths.
        case dark
        case light
        case system

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .dark: "Dark"
            case .light: "Light"
            case .system: "Same as macOS"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .dark: .dark
            case .light: .light
            case .system: nil
            }
        }
    }

    /// The operator screen's text size. Slides and outputs keep their own sizes.
    enum TextSize: String, CaseIterable, Identifiable {
        case small
        case standard
        case large
        case extraLarge

        var id: Self { self }

        var scale: CGFloat {
            switch self {
            case .small: 0.9
            case .standard: 1
            case .large: 1.15
            case .extraLarge: 1.3
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .small: "Small"
            case .standard: "Standard"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }

        /// Bigger text gets bigger buttons, so labels still fit.
        var controlSize: ControlSize {
            switch self {
            case .small: .small
            case .standard: .regular
            case .large, .extraLarge: .large
            }
        }
    }

    /// The section kinds in the order Settings lists them.
    static let sectionKinds: [SongSectionKind] = [.verse, .preChorus, .chorus, .bridge, .tag, .intro, .ending, .interlude, .other]

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Keys.textSize) }
    }

    /// Colours the operator chose; a kind that isn't here uses its default.
    private(set) var sectionColors: [String: Color]
    private(set) var customLiveColor: Color?
    private(set) var customCuedColor: Color?

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Before 1.6 the only choice was View › Follow System Appearance.
        let legacySystem = defaults.bool(forKey: Keys.legacyFollowSystem)
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init) ?? (legacySystem ? .system : .dark)
        textSize = defaults.string(forKey: Keys.textSize).flatMap(TextSize.init) ?? .standard
        var colors: [String: Color] = [:]
        for kind in Self.sectionKinds {
            if let color = defaults.string(forKey: Keys.section(kind)).flatMap(Color.init(hex:)) { colors[kind.key] = color }
        }
        sectionColors = colors
        customLiveColor = defaults.string(forKey: Keys.live).flatMap(Color.init(hex:))
        customCuedColor = defaults.string(forKey: Keys.cued).flatMap(Color.init(hex:))
    }

    // MARK: - Colours

    var liveColor: Color { customLiveColor ?? Self.defaultLive }
    var cuedColor: Color { customCuedColor ?? Self.defaultCued }

    func color(for kind: SongSectionKind) -> Color {
        sectionColors[kind.key] ?? Self.defaultColor(for: kind)
    }

    func setColor(_ color: Color, for kind: SongSectionKind) {
        sectionColors[kind.key] = color
        defaults.set(color.hex, forKey: Keys.section(kind))
    }

    func setLiveColor(_ color: Color) {
        customLiveColor = color
        defaults.set(color.hex, forKey: Keys.live)
    }

    func setCuedColor(_ color: Color) {
        customCuedColor = color
        defaults.set(color.hex, forKey: Keys.cued)
    }

    /// Whether anything on the Appearance tab differs from how Presenter comes.
    var isCustomized: Bool {
        appearance != .dark || textSize != .standard || !sectionColors.isEmpty || customLiveColor != nil || customCuedColor != nil
    }

    /// Puts appearance, text size and every colour back. The language is left alone: it has its own tab.
    func resetToDefaults() {
        appearance = .dark
        textSize = .standard
        sectionColors = [:]
        customLiveColor = nil
        customCuedColor = nil
        for kind in Self.sectionKinds { defaults.removeObject(forKey: Keys.section(kind)) }
        for key in [Keys.live, Keys.cued, Keys.legacyFollowSystem] { defaults.removeObject(forKey: key) }
    }

    /// LIVE red and CUED blue: never the system accent, so CUED can't look like LIVE.
    static let defaultLive = Color(red: 0.92, green: 0.20, blue: 0.18)
    static let defaultCued = Color(red: 0.16, green: 0.48, blue: 0.96)

    /// Kept clear of red LIVE, blue CUED and amber warnings. (EDITED shares purple with Chorus, but it's a badge with a
    /// pencil icon, not a capsule.) The Windows app uses the same colours, as hex (Windows/…/Settings.cs).
    static func defaultColor(for kind: SongSectionKind) -> Color {
        switch kind {
        case .verse: .indigo
        case .preChorus: .teal
        case .chorus: .purple
        case .bridge: .brown
        case .tag, .ending: .pink
        case .intro, .interlude: .cyan
        case .other: .gray
        }
    }

    /// A section kind's name in Settings.
    static func title(for kind: SongSectionKind) -> LocalizedStringKey {
        switch kind {
        case .verse: "Verse"
        case .preChorus: "Pre-Chorus"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .tag: "Tag"
        case .intro: "Intro"
        case .ending: "Ending"
        case .interlude: "Interlude"
        case .other: "Other labels"
        }
    }

    enum Keys {
        static let appearance = "appearance"
        static let textSize = "textSize"
        static let live = "liveColor"
        static let cued = "cuedColor"
        static let legacyFollowSystem = "followSystemAppearance"
        static func section(_ kind: SongSectionKind) -> String { "sectionColor.\(kind.key)" }
    }
}

// MARK: - Language

/// The language Presenter's menus and windows are in. macOS keeps a per-app choice in the `AppleLanguages` default
/// and reads it at launch, so a change applies after Presenter starts again.
enum LanguageChoice: String, CaseIterable, Identifiable {
    /// The first of macOS's preferred languages that Presenter is written in.
    case system
    case english = "en"
    case spanish = "es"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "Same as macOS")
        // Each language by its own name, so it can be found whatever language the screen is in.
        case .english: "English"
        case .spanish: "Español"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> LanguageChoice {
        // Only a list this app set (one language) counts; otherwise it's the system's list.
        guard let codes = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              codes.count == 1, let choice = LanguageChoice(rawValue: codes[0]) else { return .system }
        return choice
    }

    func apply(in defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// The language the engine's words should be in: the one the app's screens actually loaded.
    static var running: AppLanguage {
        AppLanguage.preferred(from: Bundle.main.preferredLocalizations)
    }
}

// MARK: - Fonts

extension Font {
    /// A text style at the operator's chosen text size. macOS has no Dynamic Type, so the sizes are the system's
    /// own for each style (measured from `NSFont.preferredFont(forTextStyle:)`), scaled.
    @MainActor
    static func ui(_ style: Font.TextStyle) -> Font {
        let scale = AppSettings.shared.textSize.scale
        guard scale != 1 else { return .system(style) }
        let (size, weight) = baseSize(style)
        return .system(size: (size * scale).rounded(), weight: weight)
    }

    private static func baseSize(_ style: Font.TextStyle) -> (CGFloat, Font.Weight) {
        switch style {
        case .largeTitle: (26, .regular)
        case .title: (22, .regular)
        case .title2: (17, .regular)
        case .title3: (15, .regular)
        case .headline: (13, .bold)
        case .subheadline: (11, .regular)
        case .body: (13, .regular)
        case .callout: (12, .regular)
        case .footnote: (10, .regular)
        case .caption: (10, .regular)
        case .caption2: (10, .medium)
        @unknown default: (13, .regular)
        }
    }
}

extension View {
    /// The operator's appearance and text size, for the top of each window.
    func operatorLook() -> some View {
        modifier(OperatorLook())
    }
}

private struct OperatorLook: ViewModifier {
    @State private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content
            .font(.ui(.body))
            .controlSize(settings.textSize.controlSize)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}

// MARK: - Hex colours

extension Color {
    /// "#RRGGBB" in sRGB, how colour settings are kept (the same on Windows).
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }
}
