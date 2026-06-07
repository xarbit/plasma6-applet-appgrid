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

// Width of a labelled grid cell. Cells are square — width tracks height so
// the label gets the full cell width (Kickoff: cellWidth == cellHeight ==
// gridCellSize). A width narrower than the two-line height budget orphans
// long single-word names like "KwalletManager" onto a second line (#177).
function labelledCellWidth(iconSize, gridUnit, smallSpacing, textScale) {
    return labelledCellHeight(iconSize, gridUnit, smallSpacing, textScale)
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
