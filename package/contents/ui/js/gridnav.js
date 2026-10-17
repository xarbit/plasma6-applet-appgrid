/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared keyboard-navigation helpers for AppGridView and
    CategoryGridView. Pure functions; state stays on the grid.
*/

.pragma library

// Arrow-key move that extends the multi-selection from the anchor
// when one is active, and falls back to a plain move otherwise.
// Caller passes its `selection` object, the live `multiSelectActive`
// flag, the original `event`, the move callback, and a getter that
// returns the current index after the move.
function arrowMoveWithSelection(selection, multiSelectActive, event, moveFn, currentIndexFn) {
    if (multiSelectActive)
        selection.extendOrMove(event, moveFn, currentIndexFn)
    else
        moveFn()
}

// Recents-row landing index when moving UP out of the grid's top row.
// Keeps the column and drops onto the last (possibly ragged) recents row,
// clamped so a short last row lands on its final cell rather than a gap.
// Shared verbatim by both grids — the lastRow arithmetic is the off-by-one
// surface, so it lives here under test.
function recentsLandingFromGrid(currentIndex, recentCount, columns) {
    const lastRow = Math.floor((recentCount - 1) / columns)
    return Math.min(currentIndex + lastRow * columns, recentCount - 1)
}

// Grid landing index when moving DOWN out of the recents row into the grid.
// Mirrors the recents column onto the grid's first row, clamped to the grid
// so a wider recents row than grid still lands on a real cell.
function gridLandingFromRecents(recentIndex, columns, gridCount) {
    return Math.min(recentIndex % columns, gridCount - 1)
}

// The cursor of a grid with an optional recents row above it, moved by one
// arrow key. One rule for both grids:
//   - with no cursor yet, any arrow but Up lands on the first cell (the
//     recents row's when it shows); Up returns to the search field;
//   - Up from the top row (of the recents, or of the grid without recents)
//     returns to the search field;
//   - Up and Down cross between the recents row and the grid, keeping the
//     column (recentsLandingFromGrid / gridLandingFromRecents);
//   - Left and Right stay within their row set, swapped in a right-to-left
//     layout; a move past an edge stays put.
// @p cursor is { recent, grid } (-1 = not there), @p key one of Qt.Key_Up /
// Down / Left / Right, @p geometry { recentCount, gridCount, columns,
// mirrored }. Returns the new { recent, grid, exit }, exit true when the
// key leaves the grid for the search field.
function moveCursor(cursor, key, geometry) {
    const recentCount = geometry.recentCount
    const gridCount = geometry.gridCount
    const columns = Math.max(1, geometry.columns)
    let recent = cursor.recent
    let grid = cursor.grid
    const result = (r, g) => ({ recent: r, grid: g, exit: false })
    const exit = { recent: -1, grid: -1, exit: true }

    if (recent < 0 && grid < 0) {
        if (key === Qt.Key_Up)
            return exit
        if (recentCount > 0)
            return result(0, -1)
        return result(-1, gridCount > 0 ? 0 : -1)
    }

    let step = 0
    if (key === Qt.Key_Left)
        step = geometry.mirrored ? 1 : -1
    else if (key === Qt.Key_Right)
        step = geometry.mirrored ? -1 : 1
    if (step !== 0) {
        if (recent >= 0)
            return result(Math.max(0, Math.min(recentCount - 1, recent + step)), -1)
        return result(-1, Math.max(0, Math.min(gridCount - 1, grid + step)))
    }

    if (key === Qt.Key_Up) {
        if (recent >= 0)
            return recent < columns ? exit : result(recent - columns, -1)
        if (grid >= columns)
            return result(-1, grid - columns)
        if (recentCount > 0)
            return result(recentsLandingFromGrid(grid, recentCount, columns), -1)
        return exit
    }

    if (key === Qt.Key_Down) {
        if (recent >= 0) {
            if (recent + columns < recentCount)
                return result(recent + columns, -1)
            if (gridCount > 0)
                return result(-1, gridLandingFromRecents(recent, columns, gridCount))
            return result(recent, -1)
        }
        return result(-1, grid + columns < gridCount ? grid + columns : grid)
    }

    return result(recent, grid)
}
