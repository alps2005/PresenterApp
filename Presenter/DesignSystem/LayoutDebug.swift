import os
import SwiftUI

// Catches the bug ADR 0002 is about: a row that can't shrink makes a panel wider than its column, and the
// clipping eats the panel's margins. Easy to miss on a wide Retina screen or on macOS 26+, where the inspector
// floats with margins of its own, so Debug builds outline the panel in amber and log it.

extension View {
    /// Debug builds: outlines this view in amber, and logs under the `Layout` category, when it doesn't fit the
    /// width it was offered, or `minimumWidth` if that's narrower. Apply it to a panel's padded content, inside any
    /// scroll view. Release builds lay the view out unchanged.
    ///
    /// Pass a resizable column's narrowest width as `minimumWidth`: a row that can't shrink may otherwise just
    /// widen the column on a big screen, and only overflow on a smaller one.
    @ViewBuilder
    func overflowGuard(_ name: String, minimumWidth: CGFloat? = nil) -> some View {
        #if DEBUG
        OverflowGuardLayout(name: name, minimumWidth: minimumWidth) {
            self
            Rectangle()
                .strokeBorder(Palette.warning, lineWidth: 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Lays out its first subview as usual, and stretches its second (the outline) over it only when the first
/// doesn't fit the width offered (or the minimum width). A layout rather than a GeometryReader, so it can ask
/// how wide the content is at any width offered, without a layout pass of its own.
private struct OverflowGuardLayout: Layout {
    let name: String
    let minimumWidth: CGFloat?
    private static let narrowestPanel: CGFloat = 100
    /// Each overflow is logged once, not on every layout pass.
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
        let offered = [proposal.width, minimumWidth].compactMap { $0 }.min()
        let width = offered.map { subviews[0].sizeThatFits(ProposedViewSize(width: $0, height: proposal.height)).width }
        // SwiftUI probes split view columns with a few points while it sizes the window; no panel is that narrow.
        guard let offered, offered >= Self.narrowestPanel, let width, width > offered + 0.5 else {
            subviews[1].place(at: bounds.origin, proposal: .zero)
            return
        }
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        let report = "\(name) is \(Int(width.rounded())) pt wide in \(Int(offered.rounded())) pt"
        if Self.reported.withLock({ $0.insert(report).inserted }) {
            Log.layout.warning("\(report, privacy: .public): a row can't shrink (docs/adr/0002-spacing-and-panel-padding.md)")
        }
    }
}
#endif
