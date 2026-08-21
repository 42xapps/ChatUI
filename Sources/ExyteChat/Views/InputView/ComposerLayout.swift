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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let width = proposal.width ?? 0
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)

        if isExpanded {
            let text = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let controlsRowHeight = max(leading.height, trailing.height)
            return CGSize(width: width, height: text.height + spacing + controlsRowHeight)
        } else {
            let textWidth = max(0, width - leading.width - trailing.width - spacing * 2)
            let text = subviews[1].sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            let height = max(leading.height, text.height, trailing.height)
            return CGSize(width: width, height: height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)

        if isExpanded {
            let text = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: text.height)
            )

            let rowY = bounds.minY + text.height + spacing
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
                proposal: ProposedViewSize(width: textWidth, height: nil)
            )
            subviews[2].place(at: CGPoint(x: bounds.maxX, y: midY), anchor: .trailing, proposal: .unspecified)
        }
    }
}
