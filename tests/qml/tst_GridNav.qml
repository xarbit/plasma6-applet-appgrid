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
import "../../package/contents/ui/js/gridnav.js" as GridNav

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

    // --- moveCursor: the one arrow-key rule of both grids ---

    // 6 recents over a 4-column layout (rows 0-3, 4-5), 10 grid cells.
    readonly property var geo: ({ recentCount: 6, gridCount: 10, columns: 4, mirrored: false })
    function move(recent, grid, key, geometry) {
        const c = GridNav.moveCursor({ recent: recent, grid: grid }, key, geometry || geo)
        return c.exit ? "exit" : c.recent + "/" + c.grid
    }

    function test_cursorStartsOnTheFirstCell() {
        compare(move(-1, -1, Qt.Key_Down), "0/-1", "recents first")
        compare(move(-1, -1, Qt.Key_Right), "0/-1")
        compare(move(-1, -1, Qt.Key_Left, { recentCount: 0, gridCount: 3, columns: 4 }), "-1/0", "the grid without recents")
        compare(move(-1, -1, Qt.Key_Down, { recentCount: 0, gridCount: 0, columns: 4 }), "-1/-1", "nothing to land on")
        compare(move(-1, -1, Qt.Key_Up), "exit")
    }

    function test_upLeavesFromTheTopRow() {
        compare(move(2, -1, Qt.Key_Up), "exit", "the top recents row")
        compare(move(5, -1, Qt.Key_Up), "1/-1")
        compare(move(-1, 1, Qt.Key_Up, { recentCount: 0, gridCount: 10, columns: 4 }), "exit", "the top grid row, no recents")
        compare(move(-1, 6, Qt.Key_Up), "-1/2")
    }

    function test_crossingRecentsAndGridKeepsTheColumn() {
        compare(move(-1, 1, Qt.Key_Up), "5/-1", "into the ragged last recents row")
        compare(move(-1, 3, Qt.Key_Up), "5/-1", "clamped to its last cell")
        compare(move(5, -1, Qt.Key_Down), "-1/1")
        compare(move(1, -1, Qt.Key_Down), "5/-1", "within the recents first")
        compare(move(5, -1, Qt.Key_Down, { recentCount: 6, gridCount: 0, columns: 4 }), "5/-1", "no grid to land on")
    }

    function test_downStopsAtTheLastRow() {
        compare(move(-1, 5, Qt.Key_Down), "-1/9")
        compare(move(-1, 7, Qt.Key_Down), "-1/7", "no cell below")
    }

    function test_leftRightStayInTheirRowsAndMirror() {
        compare(move(0, -1, Qt.Key_Left), "0/-1")
        compare(move(5, -1, Qt.Key_Right), "5/-1", "not into the grid")
        compare(move(-1, 0, Qt.Key_Right), "-1/1")
        compare(move(-1, 9, Qt.Key_Right), "-1/9")
        const rtl = { recentCount: 6, gridCount: 10, columns: 4, mirrored: true }
        compare(move(-1, 1, Qt.Key_Left, rtl), "-1/2", "Left moves forward right-to-left")
        compare(move(-1, 1, Qt.Key_Right, rtl), "-1/0")
    }
}
