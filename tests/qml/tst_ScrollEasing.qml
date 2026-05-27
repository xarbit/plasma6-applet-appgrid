/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for scrolleasing.js — the quadratic edge-proximity curve
    that drives EdgeAutoScroller's per-tick delta. Pins the boundary
    conditions and the curve shape so a future tweak to the easing
    can't silently change drag-reorder feel.
*/

import QtQuick
import QtTest
import "scrolleasing.js" as ScrollEasing

TestCase {
    name: "ScrollEasing"

    readonly property real edge: 40
    readonly property real viewH: 400
    readonly property real minPx: 1
    readonly property real maxPx: 10

    // --- boundary: outside the active zone returns the minimum ---

    function test_upMinimumAtEdgeBoundary() {
        // dragY at exactly the edge thickness means cursor just stepped
        // into the zone — t = 0, delta = minPx.
        compare(ScrollEasing.deltaPerTick(true, edge, edge, viewH, minPx, maxPx),
                minPx)
    }

    function test_downMinimumAtEdgeBoundary() {
        compare(ScrollEasing.deltaPerTick(false, viewH - edge, edge, viewH,
                                          minPx, maxPx),
                minPx)
    }

    // --- saturation: cursor exactly at the screen edge maxes out ---

    function test_upMaxAtTopPixel() {
        compare(ScrollEasing.deltaPerTick(true, 0, edge, viewH, minPx, maxPx),
                maxPx)
    }

    function test_downMaxAtBottomPixel() {
        compare(ScrollEasing.deltaPerTick(false, viewH, edge, viewH,
                                          minPx, maxPx),
                maxPx)
    }

    // --- past-edge clamps to the saturation value, never overshoots ---

    function test_upClampsPastTop() {
        // Negative dragY is possible when the drag leaves the surface;
        // delta must not exceed maxPx.
        compare(ScrollEasing.deltaPerTick(true, -50, edge, viewH, minPx, maxPx),
                maxPx)
    }

    function test_downClampsPastBottom() {
        compare(ScrollEasing.deltaPerTick(false, viewH + 50, edge, viewH,
                                          minPx, maxPx),
                maxPx)
    }

    // --- quadratic curve: midpoint t=0.5 → t² = 0.25 ---

    function test_quadraticMidpointMatchesFormula() {
        // dragY = edge/2 → inside = edge/2 → t = 0.5 → t² = 0.25
        const result = ScrollEasing.deltaPerTick(true, edge / 2, edge, viewH,
                                                  minPx, maxPx)
        const expected = minPx + (maxPx - minPx) * 0.25
        // Allow tiny float slack.
        verify(Math.abs(result - expected) < 1e-9,
               "midpoint should be " + expected + ", was " + result)
    }

    // --- monotonic: deeper-into-zone is always faster ---

    function test_curveIsMonotonicAcrossZone() {
        // Walk the curve at 11 points from boundary to edge. Each
        // delta must be >= the previous (strictly > except for ties
        // at saturation).
        var last = -1
        for (var step = 0; step <= 10; ++step) {
            const y = edge - (edge * step / 10)
            const d = ScrollEasing.deltaPerTick(true, y, edge, viewH,
                                                 minPx, maxPx)
            verify(d >= last,
                   "delta dropped at step " + step + ": " + d + " < " + last)
            last = d
        }
    }
}
