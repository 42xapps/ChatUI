import XCTest
@testable import ExyteChat

final class ScrollMetricsTests: XCTestCase {
    func testMinimumEdgeUsesAdjustedTopInset() {
        let metrics = ScrollMetrics(
            contentHeight: 1_200,
            viewportHeight: 600,
            adjustedTopInset: 80,
            adjustedBottomInset: 20
        )

        XCTAssertEqual(metrics.minimumOffset, -80)
        XCTAssertTrue(metrics.isAtMinimum(-80))
        XCTAssertFalse(metrics.isAtMinimum(-78))
    }

    func testMaximumEdgeUsesAdjustedBottomInset() {
        let metrics = ScrollMetrics(
            contentHeight: 1_200,
            viewportHeight: 600,
            adjustedTopInset: 80,
            adjustedBottomInset: 20
        )

        XCTAssertEqual(metrics.maximumOffset, 620)
        XCTAssertFalse(metrics.isAtMaximum(618))
        XCTAssertTrue(metrics.isAtMaximum(619))
    }

    func testEdgeDistancesAreRelativeToInsetAdjustedOffsets() {
        let metrics = ScrollMetrics(
            contentHeight: 1_200,
            viewportHeight: 600,
            adjustedTopInset: 80,
            adjustedBottomInset: 20
        )

        XCTAssertTrue(metrics.isWithinMinimumEdge(-40, distance: 40))
        XCTAssertFalse(metrics.isWithinMinimumEdge(-39, distance: 40))
        XCTAssertTrue(metrics.isWithinMaximumEdge(570, distance: 50))
        XCTAssertFalse(metrics.isWithinMaximumEdge(569, distance: 50))
    }

    func testCenteringUsesTheVisibleViewportBetweenInsets() {
        let metrics = ScrollMetrics(
            contentHeight: 1_200,
            viewportHeight: 600,
            adjustedTopInset: 80,
            adjustedBottomInset: 20
        )

        XCTAssertEqual(metrics.centeredOffset(forItemMidY: 500), 170)
    }

    func testShortContentHasOneSharedScrollEdge() {
        let metrics = ScrollMetrics(
            contentHeight: 300,
            viewportHeight: 600,
            adjustedTopInset: 80,
            adjustedBottomInset: 20
        )

        XCTAssertEqual(metrics.minimumOffset, -80)
        XCTAssertEqual(metrics.maximumOffset, -80)
        XCTAssertEqual(metrics.clamped(100), -80)
    }
}
