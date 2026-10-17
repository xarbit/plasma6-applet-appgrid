/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The multi-selection of an app grid with an optional recents row above
    it (the app grid and the By Category view). SelectionState works in one
    index space; here the recents take 0 .. recentCount-1 and the grid
    follows, so Shift+Arrow extends a range across the boundary just like
    within either part. The grid-index helpers translate at that boundary,
    and do nothing while the grid has multi-selection off.
*/

import QtQuick

SelectionState {
    id: gridSelection

    // --- Inputs (bound by the grid) ---

    // Whether this grid supports multi-selection right now.
    property bool active: false
    property var appsModel: null
    property int recentCount: 0
    // Apps in the grid itself (without the recents).
    property int itemCount: 0
    // The grid's cursor: in the recents row, or in the grid.
    property int recentIndex: -1
    property int currentIndex: -1
    // Callable: the storageId of grid item @p index, "" if it has none.
    property var gridSidAt: function(index) { return "" }

    // The cursor in the shared index space.
    readonly property int virtualIndex: recentIndex >= 0 ? recentIndex
                                        : currentIndex >= 0 ? recentCount + currentIndex
                                        : -1

    gridCount: recentCount + itemCount
    sidAt: function(index) {
        if (index < 0)
            return ""
        if (index < recentCount)
            return appsModel ? (appsModel.recentApps[index] || "") : ""
        return gridSidAt(index - recentCount)
    }

    // --- Grid-index helpers ---

    function toggleSelectionAt(gridIndex) {
        if (active) toggleAt(recentCount + gridIndex)
    }
    function toggleSelectionBySid(sid) {
        if (active) toggleSid(sid, -1)
    }
    function rangeSelectTo(gridIndex) {
        if (active) rangeTo(recentCount + gridIndex)
    }
    // Ctrl/Shift+click on a grid cell; true when the click was a selection.
    function applyClickModifiers(mouse, gridIndex) {
        return active ? applyModClick(mouse, recentCount + gridIndex) : false
    }
    // The same for a recents cell, which already sits at its own index.
    function applyRecentClickModifiers(mouse, recentIndex) {
        return active ? applyModClick(mouse, recentIndex) : false
    }
    function selectAllVisible() {
        if (active) selectAll(virtualIndex)
    }
    function selectedDesktopFileUrls() { return desktopFileUrls(appsModel) }
    function selectedIconNames() { return iconNames(appsModel) }
}
