/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared keyboard routing for the app grids (AppGridView, CategoryGridView).
    The geometry-specific moves stay in each view (GridView built-ins vs the
    sectioned layout), but the routing that must be identical — Alt+arrow paging
    and the "type anywhere to search" redirect — lives here once, so both grids
    behave the same and can't drift apart on the subtle bits (which key gets
    accepted, control-char filtering, …).
*/

import QtQuick

QtObject {
    id: keyNav

    property var searchField: null
    signal categoryNavRequested(int direction)

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
