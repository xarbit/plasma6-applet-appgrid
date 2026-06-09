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
        compare(CategoryScroll.clampContentX(-50, 500, 200), 0)
    }

    function test_clampWithinRange() {
        compare(CategoryScroll.clampContentX(120, 500, 200), 120)
    }

    function test_clampAtMax() {
        compare(CategoryScroll.clampContentX(9999, 500, 200), 300)
    }

    function test_clampNoOverflow() {
        // maxX === 0 → even an over-target lands at 0.
        compare(CategoryScroll.clampContentX(9999, 150, 200), 0)
    }

    // --- clampToReserve (clamp against the target's own reserve, #172) ---

    function test_clampToReserveStopsAtFlushNotCurrentViewport() {
        // container 544, content 1060, arrow 30. A page computed against the
        // narrower mid-scroll viewport overshoots to 576; the real end (right arrow
        // gone) is 1060 - (544 - 30) = 546. clampToReserve uses the target's own
        // (wider) viewport and stops at 546 — no overshoot for the glide to leave.
        compare(CategoryScroll.clampToReserve(576, 544, 1060, 30), 546)
    }

    function test_clampToReserveLeavesMidTargetUntouched() {
        // A mid target still has both reserves, viewport 544-60=484, maxX 576 — well
        // above 300, so it is not clamped.
        compare(CategoryScroll.clampToReserve(300, 544, 1060, 30), 300)
    }

    function test_clampToReserveFloorsAtZero() {
        compare(CategoryScroll.clampToReserve(-20, 544, 1060, 30), 0)
    }

    // --- viewportAfterRightScroll ---

    function test_viewportSubtractsArrowAtLeftEdge() {
        compare(CategoryScroll.viewportAfterRightScroll(200, 0, 40), 160)
    }

    function test_viewportFullWhenAlreadyScrolled() {
        compare(CategoryScroll.viewportAfterRightScroll(200, 10, 40), 200)
    }

    // --- reserveGeometry (arrow reserves + viewport, #172) ---

    function test_reserveAtStartRightShowsNoLeft() {
        // contentX 0, container 200, content 500, arrow 40 → no left reserve,
        // right shows (overflow), viewport = container - right reserve.
        const g = CategoryScroll.reserveGeometry(0, 200, 500, 40)
        compare(g.leftReserve, 0)
        verify(g.rightShown)
        compare(g.viewport, 160)
    }

    function test_reserveScrolledMidBothReserve() {
        const g = CategoryScroll.reserveGeometry(150, 200, 500, 40)
        compare(g.leftReserve, 40)
        verify(g.rightShown)
        compare(g.viewport, 120)   // 200 - 40 - 40
    }

    function test_reserveAtEndRightHidesWhenLastTabFlush() {
        // #172 lock: the right arrow hides exactly when the last tab is flush,
        // judged against the viewport WITHOUT the right reserve (container minus
        // the left reserve) — flush at contentX = 500 - (200 - 40) = 340.
        const g = CategoryScroll.reserveGeometry(340, 200, 500, 40)
        compare(g.leftReserve, 40)
        verify(!g.rightShown)
        compare(g.viewport, 160)   // right reserve reclaimed
        // Short of flush → arrow still shows (no premature collapse).
        verify(CategoryScroll.reserveGeometry(300, 200, 500, 40).rightShown)
    }

    function test_reserveNoOverflowNeitherReserves() {
        const g = CategoryScroll.reserveGeometry(0, 200, 150, 40)
        compare(g.leftReserve, 0)
        verify(!g.rightShown)
        compare(g.viewport, 200)
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
