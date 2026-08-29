//
//  ComposerLayout.swift
//  Chat
//

import SwiftUI

/// Arranges exactly 3 subviews — leading button, text field, trailing button — either inline
/// (compact) or as text-on-top / buttons-in-a-row-below (expanded). All 3 stay siblings of one
/// container across both modes, so SwiftUI can animate their positions directly instead of
/// popping/cross-fading them when they'd otherwise jump between different parent stacks.
struct ComposerLayout: Layout {
    var isExpanded: Bool
    var spacing: CGFloat = 8

    /// Height to give the text field in a row `width` points wide.
    ///
    /// Asking the field is not an option: `TextField(axis: .vertical)` answers with the height for
    /// the width it was *last laid out at*, recomputing only when its text changes. The two modes
    /// hand it very different widths, so it reports the other mode's wrapping until the next
    /// keystroke — a blank line of slack in the card — even though the text re-wraps correctly.
    var textHeight: (CGFloat) -> CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let width = proposal.width ?? 0
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)

        if isExpanded {
            let controlsRowHeight = max(leading.height, trailing.height)
            return CGSize(width: width, height: textHeight(width) + spacing + controlsRowHeight)
        } else {
            let textWidth = max(0, width - leading.width - trailing.width - spacing * 2)
            let height = max(leading.height, textHeight(textWidth), trailing.height)
            return CGSize(width: width, height: height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)

        if isExpanded {
            let textRowHeight = textHeight(bounds.width)
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: textRowHeight)
            )

            let rowY = bounds.minY + textRowHeight + spacing
            let controlsRowHeight = max(leading.height, trailing.height)
            let rowCenterY = rowY + controlsRowHeight / 2
            subviews[0].place(at: CGPoint(x: bounds.minX, y: rowCenterY), anchor: .leading, proposal: .unspecified)
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: rowCenterY), anchor: .trailing, proposal: .unspecified)
        } else {
            let midY = bounds.midY
            subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: .unspecified)

            let textWidth = max(0, bounds.width - leading.width - trailing.width - spacing * 2)
            subviews[1].place(
                at: CGPoint(x: bounds.minX + leading.width + spacing, y: midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: textWidth, height: textHeight(textWidth))
            )
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: .unspecified)
        }
    }
}
