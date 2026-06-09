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

    // --- pageTarget (one rule, both directions) ---

    function test_pageRightLandsLastTabFlush() {
        // vp150 from 0: item[2] (right 300) is the furthest whole tab a viewport
        // ahead → flush with the viewport's right edge (300 - 150 = 150).
        compare(CategoryScroll.pageTarget(items, 0, 150, 500, 1), 150)
    }

    function test_pageLeftLandsFirstTabFlush() {
        // vp150 from 350: item[2] (x 200) is the furthest whole tab a viewport
        // back → flush with the viewport's left edge.
        compare(CategoryScroll.pageTarget(items, 350, 150, 500, -1), 200)
    }

    function test_pageRightSnapsToEndOnLastPage() {
        compare(CategoryScroll.pageTarget(items, 250, 150, 500, 1), 350)   // maxX
    }

    function test_pageLeftSnapsToStartOnFirstPage() {
        compare(CategoryScroll.pageTarget(items, 100, 150, 500, -1), 0)
    }

    function test_pageEmptyAndNullSnapToBounds() {
        compare(CategoryScroll.pageTarget([], 0, 150, 500, 1), 350)
        compare(CategoryScroll.pageTarget([null, null], 0, 150, 500, 1), 350)
        compare(CategoryScroll.pageTarget([], 350, 150, 500, -1), 0)
        compare(CategoryScroll.pageTarget([null, null], 350, 150, 500, -1), 0)
    }

    // --- generic: right=full last, left=full first, symmetric, every width ---

    function _uniform(n, w, gap) {
        var a = [], x = 0
        for (var i = 0; i < n; i++) { a.push({ x: x, width: w }); x += w + gap }
        return a
    }
    function _contentWidth(a) { var l = a[a.length - 1]; return l.x + l.width }
    function _isTabRight(a, edge) {
        for (var i = 0; i < a.length; i++)
            if (Math.abs(a[i].x + a[i].width - edge) < 2) return true
        return false
    }
    function _isTabLeft(a, x) {
        for (var i = 0; i < a.length; i++)
            if (Math.abs(a[i].x - x) < 2) return true
        return false
    }

    function _walk(a, vp) {
        const cw = _contentWidth(a)
        const maxX = Math.max(0, cw - vp)
        var cx = 0, fwd = 0
        while (cx < maxX && fwd < 200) {
            var n = CategoryScroll.pageTarget(a, cx, vp, cw, 1)
            verify(n > cx, "right no progress at " + cx)
            verify(_isTabRight(a, n + vp), "right last tab not flush at " + n + " vp " + vp)
            cx = n; ++fwd
        }
        compare(cx, maxX, "right did not reach the end (vp " + vp + ")")
        var bwd = 0
        while (cx > 0 && bwd < 200) {
            var p = CategoryScroll.pageTarget(a, cx, vp, cw, -1)
            verify(p < cx, "left no progress at " + cx)
            verify(_isTabLeft(a, p), "left first tab not flush at " + p + " vp " + vp)
            cx = p; ++bwd
        }
        compare(cx, 0, "left did not reach the start (vp " + vp + ")")
        compare(bwd, fwd, "left/right page counts differ (vp " + vp + ")")
    }

    function test_pagingGenericAcrossWidthsAndModes() {
        _walk(_uniform(20, 30, 4), 200)    // many tiny icons (icon-only), small bar
        _walk(_uniform(20, 30, 4), 520)    // many tiny icons, wide bar
        _walk(_uniform(12, 80, 4), 400)    // icon+text
        _walk(_uniform(8, 140, 6), 300)    // wide text tabs
        _walk(_uniform(6, 100, 0), 250)    // few tabs, viewport > 2 tabs
    }

    // --- iconRowMinWidth (#176) ---

    function test_iconRowMinWidthSumsIconsAndGaps() {
        // 5 icons * 22 + 4 gaps * 6 = 110 + 24 = 134
        compare(CategoryScroll.iconRowMinWidth(5, 22, 6), 134)
    }

    function test_iconRowMinWidthSingleHasNoGap() {
        compare(CategoryScroll.iconRowMinWidth(1, 22, 6), 22)
    }

    function test_iconRowMinWidthEmptyIsZero() {
        compare(CategoryScroll.iconRowMinWidth(0, 22, 6), 0)
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
