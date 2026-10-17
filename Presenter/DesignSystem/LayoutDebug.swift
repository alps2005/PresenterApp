import os
import SwiftUI

// Catches the bug ADR 0002 is about: a row that can't shrink makes a panel wider than its column, and the
// clipping eats the panel's margins. Easy to miss on a wide Retina screen or on macOS 26+, where the inspector
// floats with margins of its own, so Debug builds outline the panel in amber and log it.

extension View {
    /// Debug builds: outlines this view in amber, and logs under the `Layout` category, when it's laid out wider
    /// than the width it was offered. Apply it to a panel's padded content, inside any scroll view. Release builds
    /// lay the view out unchanged.
    @ViewBuilder
    func overflowGuard(_ name: String) -> some View {
        #if DEBUG
        OverflowGuardLayout(name: name) {
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
/// Lays out its first subview as usual, and stretches its second (the outline) over it only when the first is
/// wider than offered. A layout rather than a GeometryReader, so it sees the width offered as well as the
/// width taken, without a layout pass of its own.
private struct OverflowGuardLayout: Layout {
    let name: String
    /// Each overflow is logged once, not on every layout pass.
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: bounds.origin, proposal: proposal)
        guard let offered = proposal.width, size.width > offered + 0.5 else {
            subviews[1].place(at: bounds.origin, proposal: .zero)
            return
        }
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(width: size.width, height: size.height))
        let report = "\(name) is \(Int(size.width.rounded())) pt wide in \(Int(offered.rounded())) pt"
        if Self.reported.withLock({ $0.insert(report).inserted }) {
            Log.layout.warning("\(report, privacy: .public): a row can't shrink (docs/adr/0002-spacing-and-panel-padding.md)")
        }
    }
}
#endif
