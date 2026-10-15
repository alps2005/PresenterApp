import AppKit
import SwiftUI

// Turns down Liquid Glass where Presenter controls it. Building with the macOS 26+ SDK gives toolbars, sidebars
// and scroll edges translucent glass; over moving slides in a dark booth that costs glanceability. Popovers,
// menus and sheets stay as the system draws them. Each modifier is a no-op on systems without the API.

extension View {
    /// An opaque panel background, so nothing moving shows through.
    func solidPanel(_ color: Color = Palette.panel) -> some View {
        background(color)
    }

    /// Hard scroll edges instead of the soft glass blur where content scrolls under bars.
    @ViewBuilder
    func hardScrollEdges() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .all)
        } else {
            self
        }
    }

    /// A solid window toolbar.
    @ViewBuilder
    func solidToolbar() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self
        }
    }

    /// The sidebar list on a solid background instead of the floating glass sidebar material.
    func solidSidebar() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.sidebar)
    }
}

extension Color {
    /// A colour with separate light and dark appearance values.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
