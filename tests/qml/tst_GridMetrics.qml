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

    // --- textScale: only the overhead scales, the icon is untouched ---

    function test_textScaleScalesOverheadOnly() {
        // 32 + (10*3 + 4*2) * 0.5 = 32 + 19 = 51
        compare(GridMetrics.labelledCellHeight(32, 10, 4, 0.5), 51)
    }

    function test_textScaleDefaultsToOne() {
        compare(GridMetrics.labelledCellHeight(32, 10, 4),
                GridMetrics.labelledCellHeight(32, 10, 4, 1))
    }

    function test_widthTracksScaledHeight() {
        compare(GridMetrics.labelledCellWidth(48, 18, 4, 0.8),
                GridMetrics.labelledCellHeight(48, 18, 4, 0.8))
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

    // --- square cells: width tracks height so labels get the full width (#177) ---

    function test_labelledCellIsSquare() {
        compare(GridMetrics.labelledCellWidth(64, 18, 4),
                GridMetrics.labelledCellHeight(64, 18, 4),
                "labelled cells must be square or long names orphan")
    }

    function test_labelledCellWidthSumsParts() {
        // 32 + 10*3 + 4*2 = 70
        compare(GridMetrics.labelledCellWidth(32, 10, 4), 70)
    }

    // --- columnsForWidth: how many cells fit, floored at a minimum ---

    function test_columnsFloorsToWholeCells() {
        // 650 / 126 = 5.15 → 5
        compare(GridMetrics.columnsForWidth(650, 126, 3), 5)
    }

    function test_columnsHonoursMinimum() {
        // 200 / 126 = 1.58 → 1, raised to the floor of 3
        compare(GridMetrics.columnsForWidth(200, 126, 3), 3)
    }

    function test_columnsZeroWidthFallsBackToMinimum() {
        compare(GridMetrics.columnsForWidth(0, 126, 1), 1)
    }

    function test_columnsZeroCellWidthFallsBackToMinimum() {
        compare(GridMetrics.columnsForWidth(650, 0, 3), 3)
    }
}
