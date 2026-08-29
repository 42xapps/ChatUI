import Foundation

/// Insets-aware vertical scroll geometry shared by the list's scrolling decisions.
struct ScrollMetrics {
    static let edgeTolerance: CGFloat = 1

    let minimumOffset: CGFloat
    let maximumOffset: CGFloat

    private let viewportHeight: CGFloat
    private let adjustedTopInset: CGFloat
    private let adjustedBottomInset: CGFloat

    init(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        adjustedTopInset: CGFloat,
        adjustedBottomInset: CGFloat
    ) {
        self.viewportHeight = viewportHeight
        self.adjustedTopInset = adjustedTopInset
        self.adjustedBottomInset = adjustedBottomInset

        minimumOffset = -adjustedTopInset
        maximumOffset = max(
            minimumOffset,
            contentHeight - viewportHeight + adjustedBottomInset
        )
    }

    func isAtMinimum(
        _ contentOffset: CGFloat,
        tolerance: CGFloat = edgeTolerance
    ) -> Bool {
        contentOffset <= minimumOffset + tolerance
    }

    func isAtMaximum(
        _ contentOffset: CGFloat,
        tolerance: CGFloat = edgeTolerance
    ) -> Bool {
        contentOffset >= maximumOffset - tolerance
    }

    func isWithinMinimumEdge(_ contentOffset: CGFloat, distance: CGFloat) -> Bool {
        contentOffset <= minimumOffset + distance
    }

    func isWithinMaximumEdge(_ contentOffset: CGFloat, distance: CGFloat) -> Bool {
        contentOffset >= maximumOffset - distance
    }

    func centeredOffset(forItemMidY itemMidY: CGFloat) -> CGFloat {
        let visibleMidpoint =
            (adjustedTopInset + viewportHeight - adjustedBottomInset) / 2
        return itemMidY - visibleMidpoint
    }

    func clamped(_ contentOffset: CGFloat) -> CGFloat {
        min(maximumOffset, max(minimumOffset, contentOffset))
    }
}
