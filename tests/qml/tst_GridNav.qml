/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for gridnav.js — the keyboard-nav helpers shared by AppGridView and
    CategoryGridView. The two recents<->grid boundary landings carry the
    off-by-one math (lastRow, % columns, clamps) that used to be duplicated
    inline in both grids; this pins it across ragged / single-row /
    single-column / clamped grids. Also locks the arrowMoveWithSelection
    routing, which had no test.
*/

import QtQuick
import QtTest
import "gridnav.js" as GridNav

TestCase {
    name: "GridNav"

    // --- recentsLandingFromGrid: UP from grid top row into recents ---

    function test_landingFullLastRowKeepsColumn() {
        // 12 recents, 6 cols → last row is row 1; column 2 lands on index 8.
        compare(GridNav.recentsLandingFromGrid(2, 12, 6), 8)
    }

    function test_landingRaggedLastRowClampsToFinalCell() {
        // 10 recents, 6 cols → last row holds indices 6..9. Column 5 would be
        // index 11, clamped down to the last real cell, 9.
        compare(GridNav.recentsLandingFromGrid(5, 10, 6), 9)
        compare(GridNav.recentsLandingFromGrid(2, 10, 6), 8)
    }

    function test_landingSingleRecentsRow() {
        // 4 recents, 6 cols → lastRow 0; column kept as-is.
        compare(GridNav.recentsLandingFromGrid(2, 4, 6), 2)
    }

    function test_landingSingleColumn() {
        // 1 column → recents is a vertical strip; land on the last index.
        compare(GridNav.recentsLandingFromGrid(0, 5, 1), 4)
    }

    // --- gridLandingFromRecents: DOWN from recents into grid ---

    function test_gridLandingMirrorsColumn() {
        compare(GridNav.gridLandingFromRecents(8, 6, 20), 2)
        compare(GridNav.gridLandingFromRecents(3, 6, 20), 3)
    }

    function test_gridLandingClampsToSmallGrid() {
        // Recents column 5 but grid only has 3 cells → clamp to last (2).
        compare(GridNav.gridLandingFromRecents(5, 6, 3), 2)
    }

    function test_gridLandingSingleColumn() {
        compare(GridNav.gridLandingFromRecents(4, 1, 10), 0)
    }

    function test_gridLandingColumnWrapAtRowEnd() {
        // recentIndex == columns → wraps back to column 0.
        compare(GridNav.gridLandingFromRecents(6, 6, 20), 0)
    }

    // --- degenerate empty-grid / empty-recents landings ---

    function test_gridLandingEmptyGridIsNegative() {
        // No grid cells → clamp yields -1 (caller treats as "nothing to land on").
        compare(GridNav.gridLandingFromRecents(2, 6, 0), -1)
    }

    function test_recentsLandingEmptyRecentsIsInvalid() {
        // No recents row → an invalid (negative) index. Callers must gate on
        // recentCount > 0 before landing here; this documents that contract.
        verify(GridNav.recentsLandingFromGrid(2, 0, 6) < 0)
    }

    // --- arrowMoveWithSelection routing ---

    function test_arrowMovePlainWhenNoMultiSelect() {
        var moved = false
        GridNav.arrowMoveWithSelection(null, false, {},
            function() { moved = true }, function() { return 0 })
        verify(moved)
    }

    function test_arrowMoveDelegatesToSelectionWhenMultiSelect() {
        var extended = false
        var moved = false
        const stub = { extendOrMove: function(e, m, c) { extended = true } }
        GridNav.arrowMoveWithSelection(stub, true, {},
            function() { moved = true }, function() { return 0 })
        verify(extended)
        // The move is handed to selection.extendOrMove, not called directly.
        verify(!moved)
    }
}
