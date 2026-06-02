/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared grid-cell sizing. The labelled cell height is used by AppGridView,
    the category grid, and GridPanel's pre-layout size estimate; they must
    stay equal or the bottom row clips. Single source of truth here.
*/

.pragma library

// Height of a grid cell showing an icon plus its (up to two-line) label.
// Kirigami.Units values are passed in so this stays a pure, testable
// function with no QML context dependency.
function labelledCellHeight(iconSize, gridUnit, smallSpacing) {
    return iconSize + gridUnit * 3 + smallSpacing * 2
}
