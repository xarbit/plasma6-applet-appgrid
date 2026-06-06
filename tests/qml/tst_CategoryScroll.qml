/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for categoryscroll.js — the category-bar scroll geometry that used
    to be inline over a live Flickable and so could not be asserted. The
    headline case is #172: a wide scroll arrow narrowing the viewport must not
    leave a trailing gap / lingering right arrow after a full right scroll.
*/

import QtQuick
import QtTest
import "categoryscroll.js" as CategoryScroll

TestCase {
    name: "CategoryScroll"

    // Five 100px buttons at x = 0,100,…,400 → contentWidth 500.
    readonly property var items: [
        { x: 0,   width: 100 },
        { x: 100, width: 100 },
        { x: 200, width: 100 },
        { x: 300, width: 100 },
        { x: 400, width: 100 },
    ]

    // --- maxContentX ---

    function test_maxContentXWhenOverflowing() {
        compare(CategoryScroll.maxContentX(500, 200), 300)
    }

    function test_maxContentXClampsToZeroWhenFits() {
        compare(CategoryScroll.maxContentX(150, 200), 0)
    }

    // --- clampWheelDelta ---

    function test_wheelDeltaPassesThroughWhenSmall() {
        // 120 (one notch) is well under the 0.6*200 = 120... use 100 to stay under.
        compare(CategoryScroll.clampWheelDelta(100, 200, 40), 100)
    }

    function test_wheelDeltaCappedToViewportFraction() {
        // cap = max(0.6*200, 40) = 120; a 900px hi-res delta is capped to 120.
        compare(CategoryScroll.clampWheelDelta(900, 200, 40), 120)
    }

    function test_wheelDeltaCapPreservesSign() {
        compare(CategoryScroll.clampWheelDelta(-900, 200, 40), -120)
    }

    function test_wheelDeltaFloorForNarrowBar() {
        // cap = max(0.6*50, 40) = 40; small viewport still moves by the floor.
        compare(CategoryScroll.clampWheelDelta(900, 50, 40), 40)
    }

    // --- clampContentX ---

    function test_clampBelowZero() {
        const r = CategoryScroll.clampContentX(-50, 500, 200)
        compare(r.contentX, 0)
        verify(!r.anchoredRight)
    }

    function test_clampWithinRange() {
        const r = CategoryScroll.clampContentX(120, 500, 200)
        compare(r.contentX, 120)
        verify(!r.anchoredRight)
    }

    function test_clampAtMaxArmsAnchor() {
        const r = CategoryScroll.clampContentX(9999, 500, 200)
        compare(r.contentX, 300)
        verify(r.anchoredRight)
    }

    function test_clampNoOverflowNeverAnchors() {
        // maxX === 0 → even an over-target lands at 0 without arming the anchor.
        const r = CategoryScroll.clampContentX(9999, 150, 200)
        compare(r.contentX, 0)
        verify(!r.anchoredRight)
    }

    // --- viewportAfterRightScroll ---

    function test_viewportSubtractsArrowAtLeftEdge() {
        compare(CategoryScroll.viewportAfterRightScroll(200, 0, 40), 160)
    }

    function test_viewportFullWhenAlreadyScrolled() {
        compare(CategoryScroll.viewportAfterRightScroll(200, 10, 40), 200)
    }

    // --- arrowVisibility ---

    function test_arrowsAtStart() {
        const v = CategoryScroll.arrowVisibility(0, 200, 500)
        verify(!v.left)
        verify(v.right)
    }

    function test_arrowsScrolledMid() {
        const v = CategoryScroll.arrowVisibility(150, 200, 500)
        verify(v.left)
        verify(v.right)
    }

    function test_arrowsAtEnd() {
        const v = CategoryScroll.arrowVisibility(300, 200, 500)
        verify(v.left)
        verify(!v.right)
    }

    // --- trailingGap ---

    function test_trailingGapZeroAtMax() {
        compare(CategoryScroll.trailingGap(300, 500, 200), 0)
    }

    function test_trailingGapPositiveWhenOverscrolled() {
        // Synthetic overscroll (clamp prevents this in practice) → exposes gap.
        compare(CategoryScroll.trailingGap(350, 500, 200), 50)
    }

    // --- #172 regression lock ---

    function test_172RightAnchorCollapsesArrowAfterLeftArrowExpands() {
        const contentWidth = 210
        const rawViewport = 200
        const arrowWidth = 40

        // 1. Full right scroll while the left arrow is still collapsed.
        const first = CategoryScroll.clampContentX(contentWidth, contentWidth, rawViewport)
        compare(first.contentX, 10)   // maxX = 210 - 200
        verify(first.anchoredRight)   // armed to track the shrinking viewport

        // 2. Left arrow expands → viewport narrows by arrowWidth → re-anchor.
        const narrowed = rawViewport - arrowWidth        // 160
        const newMax = CategoryScroll.maxContentX(contentWidth, narrowed)  // 50
        compare(newMax, 50)
        compare(CategoryScroll.trailingGap(newMax, contentWidth, narrowed), 0)
        verify(!CategoryScroll.arrowVisibility(newMax, narrowed, contentWidth).right)
    }

    function test_172WithoutAnchorRightArrowWouldLinger() {
        // Documents the bug the anchor fixes: staying at the old (raw-viewport)
        // maxX leaves the right arrow visible once the viewport narrows.
        const contentWidth = 210, rawViewport = 200, arrowWidth = 40
        const stuck = CategoryScroll.maxContentX(contentWidth, rawViewport)  // 10
        const narrowed = rawViewport - arrowWidth                           // 160
        verify(CategoryScroll.arrowVisibility(stuck, narrowed, contentWidth).right)
    }

    // --- pageRightTarget ---

    function test_pageRightAnchorsBoundaryItem() {
        // W=150 from contentX 0: items 0..2 fit, target aligns item[2]'s right.
        compare(CategoryScroll.pageRightTarget(items, 0, 150, 500, 5), 155)
    }

    function test_pageRightSnapsToEndWhenTouchingLast() {
        // Large viewport reaches the last item → snap to contentWidth.
        compare(CategoryScroll.pageRightTarget(items, 0, 250, 500, 5), 500)
    }

    function test_pageRightEmptySnapsToEnd() {
        compare(CategoryScroll.pageRightTarget([], 0, 150, 500, 5), 500)
    }

    function test_pageRightSkipsNullDelegates() {
        // Unrealised delegates arrive as null; they're skipped, so an all-null
        // array behaves like an empty one → snap to the end.
        compare(CategoryScroll.pageRightTarget([null, null], 0, 150, 500, 5), 500)
    }

    // --- pageLeftTarget ---

    function test_pageLeftAnchorsFirstVisibleItem() {
        compare(CategoryScroll.pageLeftTarget(items, 300, 150, 5), 195)
    }

    function test_pageLeftSnapsToStartNearBeginning() {
        compare(CategoryScroll.pageLeftTarget(items, 100, 150, 5), 0)
    }

    // --- ensureVisibleTarget ---

    function test_ensureVisibleScrollsRightForOffscreenRight() {
        // item[4] (x400..500) past a 250 viewport at contentX 0.
        compare(CategoryScroll.ensureVisibleTarget(400, 100, 0, 250, 250, 5), 255)
    }

    function test_ensureVisibleScrollsLeftForOffscreenLeft() {
        compare(CategoryScroll.ensureVisibleTarget(0, 100, 100, 250, 250, 5), -5)
    }

    function test_ensureVisibleNullWhenInView() {
        compare(CategoryScroll.ensureVisibleTarget(120, 100, 100, 250, 250, 5), null)
    }
}
