/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared keyboard routing for the app grids (AppGridView, CategoryGridView):
    the arrows over a recents row and the grid (one rule, GridNav.moveCursor),
    Shift+arrow extending the selection, Alt+arrow paging the categories and
    the "type anywhere to search" redirect. Both grids behave the same and
    can't drift apart; each only applies the cursor it is asked to.
*/

import QtQuick

import "../js/gridnav.js" as GridNav

QtObject {
    id: keyNav

    property var searchField: null

    // The grid's cursor (-1 = not there) and shape, bound by the grid.
    property int recentIndex: -1
    property int gridIndex: -1
    property int recentCount: 0
    property int gridCount: 0
    property int columns: 1
    property bool mirrored: false
    // The grid's GridSelection, and whether multi-selection is on.
    property var selection: null
    property bool selectionActive: false

    signal categoryNavRequested(int direction)
    // Move the grid's cursor here.
    signal cursorRequested(int recentIndex, int gridIndex)
    // An arrow left the grid (Up from its top row): back to the search field.
    signal exitRequested()

    // An arrow key on the grid. Alt+Left/Right pages the categories; Shift
    // extends the selection through the cell moved to.
    function handleArrow(event) {
        const direction = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0
        if (direction !== 0 && handleAltArrow(event, direction))
            return
        event.accepted = true
        const next = GridNav.moveCursor({ recent: recentIndex, grid: gridIndex }, event.key,
            { recentCount: recentCount, gridCount: gridCount, columns: columns, mirrored: mirrored })
        if (next.exit) {
            exitRequested()
            return
        }
        const move = () => cursorRequested(next.recent, next.grid)
        // The first landing is a plain move: there is nothing to extend from.
        if (recentIndex < 0 && gridIndex < 0 || !selection)
            move()
        else
            GridNav.arrowMoveWithSelection(selection, selectionActive, event, move,
                                           () => selection.virtualIndex)
    }

    // Alt+Left/Right pages the category bar instead of moving the cursor. Returns
    // true when it handled the event (the caller then skips its own move).
    function handleAltArrow(event, direction) {
        if (!(event.modifiers & Qt.AltModifier))
            return false
        keyNav.categoryNavRequested(direction)
        event.accepted = true
        return true
    }

    // Redirect a printable keystroke to the search field (type anywhere to
    // search). Control chars (Enter / Esc / Tab / Backspace, < 0x20) and modified
    // keys are left for the specific handlers. Returns true when it forwarded.
    function forwardTyping(event) {
        if (!searchField || event.modifiers || event.text.length === 0
                || event.text.charCodeAt(0) < 0x20)
            return false
        searchField.forceActiveFocus()
        searchField.text += event.text
        event.accepted = true
        return true
    }
}
