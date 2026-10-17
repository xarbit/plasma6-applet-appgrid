/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    The "Shuffle" hover animation of the app grid: hovering an icon swaps it
    with a random other icon on screen. The swap is visual only (the apps stay
    where they are) and is undone when the grid resets. With an overlay the
    two icons fly to each other's place first; without one they swap at once.
*/

import QtQuick

import "../js/constants.js" as Const

QtObject {
    id: shuffle

    // The AppGridView: count, indexAt(), itemAtIndex(), contentX/Y, the app
    // model and the cell style.
    property var grid: null
    // The ShuffleOverlay the icons fly across, or null.
    property Item overlay: null

    // Grid index -> the icon shown there instead of the app's own.
    property var swaps: ({})

    // The icon shown at @p index instead of its own, or "".
    function iconAt(index) {
        return swaps[index] !== undefined ? swaps[index] : ""
    }

    // Swap the icon at @p fromIndex with a random other visible one.
    function shuffle(fromIndex) {
        if (!grid || grid.count < 2)
            return
        let first = grid.indexAt(grid.contentX, grid.contentY)
        let last = grid.indexAt(grid.contentX + grid.width - 1, grid.contentY + grid.height - 1)
        if (first < 0) first = 0
        if (last < 0) last = grid.count - 1
        const candidates = []
        for (let i = first; i <= last; ++i) {
            if (i !== fromIndex && grid.itemAtIndex(i))
                candidates.push(i)
        }
        if (candidates.length === 0)
            return
        const otherIndex = candidates[Math.floor(Math.random() * candidates.length)]

        const appsModel = grid.appsModel
        const fromData = appsModel ? appsModel.get(fromIndex) : null
        const otherData = appsModel ? appsModel.get(otherIndex) : null
        if (!fromData || !otherData)
            return
        const fromIcon = iconAt(fromIndex) || fromData.iconName || Const.DEFAULT_ICON
        const otherIcon = iconAt(otherIndex) || otherData.iconName || Const.DEFAULT_ICON

        const fromItem = grid.itemAtIndex(fromIndex)
        const otherItem = grid.itemAtIndex(otherIndex)
        if (!fromItem || !otherItem || !overlay) {
            apply(fromIndex, otherIndex, fromIcon, otherIcon)
            return
        }
        const iconSize = grid.cellStyle.iconSize
        const fromPos = fromItem.mapToItem(overlay, fromItem.width / 2 - iconSize / 2, 0)
        const otherPos = otherItem.mapToItem(overlay, otherItem.width / 2 - iconSize / 2, 0)
        overlay.startAnim(fromPos.x, fromPos.y, otherPos.x, otherPos.y,
                          fromIcon, otherIcon, fromIndex, otherIndex)
    }

    function apply(fromIndex, otherIndex, fromIcon, otherIcon) {
        const next = Object.assign({}, swaps)
        next[fromIndex] = otherIcon
        next[otherIndex] = fromIcon
        swaps = next
    }

    function clear() {
        swaps = {}
    }

    // The overlay's flight landed: swap the icons for real.
    property Connections _overlayConnection: Connections {
        target: shuffle.overlay
        ignoreUnknownSignals: true
        function onSwapFinished(fromIndex, toIndex, fromIcon, toIcon) {
            shuffle.apply(fromIndex, toIndex, fromIcon, toIcon)
        }
    }
}
