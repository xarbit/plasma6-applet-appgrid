/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared grid-cell sizing. The labelled cell height is used by AppGridView,
    the category grid, and GridPanel's pre-layout size estimate; they must
    stay equal or the bottom row clips. Single source of truth here.
*/

.pragma library

// Height of a grid cell showing an icon plus its (up to two-line) label.
// The icon keeps its discrete preset size; only the label/spacing overhead
// scales by textScale so smaller presets get proportionally tighter cells
// instead of a tiny icon floating in a fixed-overhead square. textScale
// follows the size preset (Scale.textScale) and is pinned to 1.0 when the
// user decoupled text size (#167). Kirigami.Units values are passed in so
// this stays a pure, testable function with no QML context dependency.
function labelledCellHeight(iconSize, gridUnit, smallSpacing, textScale) {
    var s = textScale === undefined ? 1 : textScale
    return iconSize + (gridUnit * 3 + smallSpacing * 2) * s
}

// Width of a labelled grid cell. By default cells are square — width tracks
// height so the label gets the full cell width (Kickoff: cellWidth ==
// cellHeight == gridCellSize), which keeps long single-word names like
// "KwalletManager" on one line (#177). reduceSpacing trims one gridUnit of the
// width overhead for a tighter horizontal grid (the pre-#177 width); the row
// height is unchanged, so labels still fit but may wrap a touch sooner.
function labelledCellWidth(iconSize, gridUnit, smallSpacing, textScale, reduceSpacing) {
    var s = textScale === undefined ? 1 : textScale
    var units = reduceSpacing ? 2 : 3
    return iconSize + (gridUnit * units + smallSpacing * 2) * s
}

// Columns that fit across width at the given cell width, never fewer than
// minColumns. Shared by the app grid (min 3) and the category grid (min 1)
// so the "how many fit" rule lives in one tested place. A non-positive
// width or cell width falls back to minColumns rather than yielding 0/NaN.
function columnsForWidth(width, cellWidth, minColumns) {
    if (width <= 0 || cellWidth <= 0)
        return minColumns
    return Math.max(minColumns, Math.floor(width / cellWidth))
}
