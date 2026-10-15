import AppKit
import SwiftUI

// Presenter's design tokens. The operator console is "quiet native": system controls and window chrome, but
// solid, dark show surfaces and fixed state colours, so the important states read at a glance in a dark booth.
// See docs/adr/0001-quiet-native-design.md.

/// Spacing between and around controls, in points.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}

/// Corner radii, in points.
enum Radius {
    /// Slide and media thumbnails, previews and cards.
    static let tile: CGFloat = 6
    static let badge: CGFloat = 4
    static let card: CGFloat = 6
}

/// Semantic colours. Each state has one colour that never depends on the system accent, so CUED can never
/// look like LIVE.
enum Palette {
    /// On the audience output now.
    static let live = Color(red: 0.92, green: 0.20, blue: 0.18)
    /// Ready to go live next.
    static let cued = Color(red: 0.16, green: 0.48, blue: 0.96)
    /// Something needs the operator's attention: missing media, a problem with an output.
    static let warning = Color(
        light: NSColor(srgbRed: 0.70, green: 0.40, blue: 0.0, alpha: 1),
        dark: NSColor(srgbRed: 0.98, green: 0.69, blue: 0.10, alpha: 1)
    )
    /// Changed since it went on screen; the audience sees the older version.
    static let edited = Color(
        light: NSColor(srgbRed: 0.50, green: 0.28, blue: 0.85, alpha: 1),
        dark: NSColor(srgbRed: 0.68, green: 0.48, blue: 0.98, alpha: 1)
    )
    /// Blackout: black, set apart from the dark panels by a live-coloured outline.
    static let blackout = Color.black
    /// States where nothing is live: the badge is quiet but still readable.
    static let idle = Color(white: 0.42)

    /// Show surfaces: opaque, so moving slides never show through.
    static let panel = Color(nsColor: .underPageBackgroundColor)
    static let panelRaised = Color(nsColor: .controlBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color.secondary.opacity(0.4)
}

enum Typography {
    /// LIVE, CUED and the other state badges.
    static let badge = Font.caption.bold()
    /// Live panel slot titles: Up Next, Cued.
    static let sectionHeader = Font.subheadline.bold()
    /// A timer's running value in Show Controls.
    static let timerValue = Font.title3.monospacedDigit().weight(.semibold)
}

/// Times shown to the operator, e.g. a clip's length or a timer: "4:05", or "1:02:03" past an hour.
enum TimeText {
    static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
