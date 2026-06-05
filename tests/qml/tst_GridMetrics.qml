/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for gridmetrics.js — the labelled grid-cell height shared by
    AppGridView, the category grid, and GridPanel's pre-layout estimate. If
    these consumers ever disagree the bottom row clips, so the formula's
    coefficients are pinned here as the single source of truth.
*/

import QtQuick
import QtTest
import "gridmetrics.js" as GridMetrics

TestCase {
    name: "GridMetrics"

    // --- absolute value: icon + 3 line-units + 2 spacings ---

    function test_labelledCellHeightSumsParts() {
        // 32 + 10*3 + 4*2 = 70
        compare(GridMetrics.labelledCellHeight(32, 10, 4), 70)
    }

    // --- coefficient locks: each input weighted exactly as documented ---

    function test_iconWeightedByOne() {
        const base = GridMetrics.labelledCellHeight(32, 10, 4)
        compare(GridMetrics.labelledCellHeight(33, 10, 4) - base, 1)
    }

    function test_gridUnitWeightedByThree() {
        const base = GridMetrics.labelledCellHeight(32, 10, 4)
        compare(GridMetrics.labelledCellHeight(32, 11, 4) - base, 3)
    }

    function test_smallSpacingWeightedByTwo() {
        const base = GridMetrics.labelledCellHeight(32, 10, 4)
        compare(GridMetrics.labelledCellHeight(32, 10, 5) - base, 2)
    }
}
