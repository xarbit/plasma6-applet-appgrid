/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared drill-in-place selection logic for a navigable grouped model (the
    favourites folders #18 and the kmenuedit menu tree #201) bound to an
    AppGridView. One place so both views behave identically:

    - On a level change, only manage selection while the grid holds keyboard
      focus (the user is navigating): going back lands on the folder just left,
      going deeper on the first entry. A mouse / category-bar switch leaves focus
      on the search field with nothing preselected, like the flat views.
    - Keeps an explicit `canGoBack` mirror; a chained `model.canGoBack` binding
      isn't reliably reactive, and the variants' Escape Shortcut depends on it.
*/

import QtQuick

QtObject {
    id: nav

    // A navigable grouped model: canGoBack / currentPath / goBack() / indexOfFolder().
    property var model: null
    // The AppGridView showing it.
    property var grid: null
    // Only manage selection when this is the active view (the favourites grid is
    // shared with All / category, so it gates on the favourites tab).
    property bool active: true

    readonly property bool canGoBack: _canGoBack
    property bool _canGoBack: false
    property string _prevPath: ""

    // Enter the grid from the search field: select the first item + focus, so a
    // single Down lands on item 0 (matches the flat grid's navigateToResults).
    function focusGrid() {
        if (!grid)
            return
        if (grid.count > 0)
            grid.currentIndex = 0
        grid.forceActiveFocus()
    }

    function goBack() {
        if (model && model.canGoBack)
            model.goBack()
    }

    // Clear navigation memory + the grid's scroll/selection (on close, so the next
    // open starts clean instead of flashing the last folder).
    function reset() {
        _prevPath = ""
        _canGoBack = false
        if (grid) {
            grid.currentIndex = -1
            grid.contentY = grid.originY
        }
    }

    property Connections _conn: Connections {
        target: nav.model
        ignoreUnknownSignals: true
        function onPathChanged() {
            const m = nav.model
            const newPath = m ? m.currentPath : ""
            const canGoBack = !!m && m.canGoBack
            if (nav.active && nav.grid) {
                if (nav.grid.activeFocus) {
                    // Keyboard nav: going back (shorter prefix path) re-selects the
                    // folder just left; going deeper selects the first entry. Snap
                    // the highlight so it lands on the cell instead of sliding.
                    let idx = 0
                    if (nav.grid.count > 0 && nav._prevPath.length > newPath.length
                            && nav._prevPath.indexOf(newPath) === 0)
                        idx = Math.max(0, m.indexOfFolder(nav._prevPath))
                    nav.grid.selectSnapped(nav.grid.count > 0 ? idx : -1)
                } else {
                    nav.grid.currentIndex = -1
                }
                // Inside a folder the grid must hold focus so Esc climbs out and
                // arrows work — even when the folder was opened by mouse (no
                // preselect then). At the top level focus is left alone, so a
                // category-bar switch keeps the search field.
                if (canGoBack)
                    nav.grid.forceActiveFocus()
            }
            nav._prevPath = newPath
            nav._canGoBack = canGoBack
        }
    }
}
