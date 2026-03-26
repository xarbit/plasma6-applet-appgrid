/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Icon grid view for applications with hover shake animation.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

GridView {
    id: gridView

    // Number of columns to display. If adaptiveColumns is true, computed from width.
    property int columns: 6
    property bool adaptiveColumns: false
    readonly property int effectiveColumns: adaptiveColumns
        ? Math.max(3, Math.floor(width / (iconSize + Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing * 2)))
        : columns

    // Icon size from configuration (Kirigami pixel size).
    property real iconSize: Kirigami.Units.iconSizes.huge

    // Emitted when a shake-all-icons trigger fires (e.g. on grid open).
    signal shakeAllIcons()

    // Emitted when an app is launched by proxy index.
    signal launched(int index)

    // Emitted when a recent app is launched by storageId.
    signal recentLaunched(string storageId)

    // Emitted when the user right-clicks an app.
    signal contextMenuRequested(int index, string storageId, string desktopFile)

    // Emitted when favorites order changes via drag reorder.
    signal favoritesOrderChanged()

    // --- Shuffle animation state ---
    // Maps proxy index -> icon name override for visual-only icon swaps.
    property var iconSwaps: ({})
    signal shufflesUpdated()

    // Emitted when a shuffle animation should play. The overlay handles the visuals.
    signal shuffleAnimRequested(real fromX, real fromY, real toX, real toY,
                                string fromIcon, string toIcon,
                                int fromIndex, int toIndex)

    // Reference to the overlay container (set by GridPanel)
    property Item shuffleOverlayParent: null

    function shuffleIcon(fromIndex) {
        if (count < 2) return

        // Build list of visible indices (excluding the hovered one)
        var firstVisible = indexAt(contentX, contentY)
        var lastVisible = indexAt(contentX + width - 1, contentY + height - 1)
        if (firstVisible < 0) firstVisible = 0
        if (lastVisible < 0) lastVisible = count - 1

        var candidates = []
        for (var i = firstVisible; i <= lastVisible; i++) {
            if (i !== fromIndex && itemAtIndex(i))
                candidates.push(i)
        }
        if (candidates.length === 0) return

        var otherIndex = candidates[Math.floor(Math.random() * candidates.length)]

        var fromData = appsModel ? appsModel.get(fromIndex) : null
        var otherData = appsModel ? appsModel.get(otherIndex) : null
        if (!fromData || !otherData) return

        var fromIcon = resolveIcon(fromIndex, fromData.iconName)
        var otherIcon = resolveIcon(otherIndex, otherData.iconName)

        var fromItem = itemAtIndex(fromIndex)
        var otherItem = itemAtIndex(otherIndex)
        if (!fromItem || !otherItem || !shuffleOverlayParent) {
            applySwap(fromIndex, otherIndex, fromIcon, otherIcon)
            return
        }

        var fromPos = fromItem.mapToItem(shuffleOverlayParent, fromItem.width / 2 - gridView.iconSize / 2, 0)
        var otherPos = otherItem.mapToItem(shuffleOverlayParent, otherItem.width / 2 - gridView.iconSize / 2, 0)

        shuffleAnimRequested(fromPos.x, fromPos.y, otherPos.x, otherPos.y,
                             fromIcon, otherIcon, fromIndex, otherIndex)
    }

    function applySwap(fromIndex, otherIndex, fromIcon, otherIcon) {
        var newSwaps = Object.assign({}, iconSwaps)
        newSwaps[fromIndex] = otherIcon
        newSwaps[otherIndex] = fromIcon
        iconSwaps = newSwaps
        shufflesUpdated()
    }

    function clearShuffles() {
        iconSwaps = {}
        shufflesUpdated()
    }

    readonly property string defaultIcon: "application-x-executable"

    function getDisplayIcon(index) {
        return iconSwaps[index] !== undefined ? iconSwaps[index] : ""
    }

    function resolveIcon(index, fallbackName) {
        if (iconSwaps[index] !== undefined) return iconSwaps[index]
        return fallbackName || defaultIcon
    }

    // Whether edit/reorder mode is active
    property bool editMode: false
    // Index of currently selected item for swap (-1 = none)
    property int selectedSwapIndex: -1

    // Auto-exit edit mode after inactivity
    Timer {
        id: editTimeout
        interval: 10000
        running: gridView.editMode
        onTriggered: {
            gridView.editMode = false
            gridView.selectedSwapIndex = -1
            gridView.favoritesOrderChanged()
        }
    }

    onSelectedSwapIndexChanged: {
        if (editMode) editTimeout.restart()
    }

    clip: true
    cacheBuffer: Kirigami.Units.gridUnit * 4
    readonly property bool labelsHidden: hideLabelsOnFavorites && favoritesActive
    cellWidth: Math.floor(width / effectiveColumns)
    cellHeight: labelsHidden
               ? cellWidth
               : iconSize + Kirigami.Units.gridUnit * 3 + Kirigami.Units.smallSpacing * 2
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: true
    currentIndex: -1
    highlightFollowsCurrentItem: true
    highlightMoveDuration: animateHighlight ? Kirigami.Units.shortDuration : 0

    property bool animateHighlight: true

    // Smooth transitions when items move during drag reorder
    move: Transition {
        NumberAnimation { properties: "x,y"; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }
    moveDisplaced: Transition {
        NumberAnimation { properties: "x,y"; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    // Search field to return focus to when typing text
    property Item searchField: null
    // The apps model for section queries
    property var appsModel: null
    // Config toggles
    property bool showRecentApps: true
    property bool startWithFavorites: false
    property bool favoritesActive: false
    property bool showDividers: true
    property bool showTooltips: true
    property bool showNewAppBadge: true
    property bool hideLabelsOnFavorites: false

    // Show recently used apps in the grid header.
    //
    // When startWithFavorites is ON:
    //   → show recents in the Favorites tab (any sort order)
    //   → hide in All (recents belong with favorites)
    //
    // When startWithFavorites is OFF:
    //   → show recents in All with Alphabetical sort
    //   → disabled when Most Used (frequent apps already at the top)
    //   → hide in Favorites (user navigated there manually)
    //
    // Never show during search or when a category filter is active.
    readonly property bool showRecents: {
        if (!showRecentApps || !appsModel || appsModel.searchText
            || appsModel.filterCategory || appsModel.recentApps.length === 0)
            return false

        if (startWithFavorites)
            return favoritesActive

        // Most Used without startWithFavorites → recents disabled
        if (appsModel.sortMode === 1)
            return false

        return !favoritesActive
    }

    // Keyboard navigation index for recent items in header (-1 = not in recents)
    property int recentIndex: -1
    readonly property int recentCount: showRecents ? appsModel.recentApps.length : 0

    function launchRecentByIndex(idx) {
        if (idx >= 0 && idx < recentCount)
            recentLaunched(appsModel.recentApps[idx])
    }

    Keys.onReturnPressed: {
        if (recentIndex >= 0)
            launchRecentByIndex(recentIndex)
        else if (currentIndex >= 0)
            launched(currentIndex)
    }
    Keys.onEnterPressed: {
        if (recentIndex >= 0)
            launchRecentByIndex(recentIndex)
        else if (currentIndex >= 0)
            launched(currentIndex)
    }
    Keys.onUpPressed: {
        if (recentIndex >= 0) {
            // Move up within recents row — go to row above if possible
            var newIdx = recentIndex - effectiveColumns
            if (newIdx >= 0) {
                recentIndex = newIdx
            } else {
                // At top row of recents, go back to search
                recentIndex = -1
                currentIndex = -1
                if (searchField) searchField.forceActiveFocus()
            }
        } else if (currentIndex >= 0 && currentIndex < effectiveColumns && showRecents) {
            // At top row of grid, move into recents
            var lastRow = Math.floor((recentCount - 1) / effectiveColumns)
            recentIndex = Math.min(currentIndex + lastRow * effectiveColumns, recentCount - 1)
            currentIndex = -1
        } else {
            moveCurrentIndexUp()
        }
    }
    Keys.onDownPressed: {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + effectiveColumns
            if (newIdx < recentCount) {
                recentIndex = newIdx
            } else {
                // Move from recents into grid
                currentIndex = Math.min(recentIndex % effectiveColumns, count - 1)
                recentIndex = -1
            }
        } else {
            moveCurrentIndexDown()
        }
    }
    Keys.onLeftPressed: {
        if (recentIndex > 0)
            recentIndex--
        else if (recentIndex < 0)
            moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        if (recentIndex >= 0 && recentIndex < recentCount - 1)
            recentIndex++
        else if (recentIndex < 0)
            moveCurrentIndexRight()
    }
    // Consume Tab to prevent it from reaching the focus chain or search bar
    Keys.onTabPressed: function(event) { event.accepted = true }
    Keys.onBacktabPressed: function(event) { event.accepted = true }

    Keys.onPressed: function(event) {
        // Redirect typing to search bar, but not Tab or special keys
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return
        if (event.text.length > 0 && !event.modifiers && searchField) {
            searchField.forceActiveFocus()
            searchField.text += event.text
            currentIndex = -1
            recentIndex = -1
        }
    }

    onCurrentIndexChanged: {
        if (currentIndex >= 0) recentIndex = -1
    }

    header: RecentAppsHeader {
        width: gridView.width
        height: gridView.showRecents ? implicitHeight : 0
        visible: gridView.showRecents
        appsModel: gridView.appsModel
        cellWidth: gridView.cellWidth
        cellHeight: gridView.cellHeight
        iconSize: gridView.iconSize
        currentRecentIndex: gridView.recentIndex
        gridHasFocus: gridView.activeFocus
        favoritesActive: gridView.favoritesActive
        showDividers: gridView.showDividers
        showTooltips: gridView.showTooltips
        onRecentLaunched: function(storageId) { gridView.recentLaunched(storageId) }
        onContextMenuRequested: function(storageId, desktopFile) {
            gridView.contextMenuRequested(-1, storageId, desktopFile)
        }

        Connections {
            target: gridView
            function onShakeAllIcons() { gridView.headerItem.shakeAll() }
        }
    }

    highlight: Item {
        Rectangle {
            anchors.centerIn: parent
            width: gridView.cellWidth - Kirigami.Units.smallSpacing * 2
            height: gridView.cellHeight - Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                           Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b, 0.2)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                  Kirigami.Theme.highlightColor.g,
                                  Kirigami.Theme.highlightColor.b, 0.6)
            visible: gridView.currentIndex >= 0 && gridView.activeFocus
        }
    }

    delegate: Item {
        id: delegateRoot
        width: gridView.cellWidth
        height: gridView.cellHeight

        AppIconDelegate {
            id: iconDelegate
            anchors.fill: parent
            appName: model.name || ""
            appIcon: model.iconName || "application-x-executable"
            displayIcon: gridView.getDisplayIcon(model.index)
            appGenericName: model.genericName || ""
            appComment: model.comment || ""
            installSource: model.installSource || ""
            showTooltip: gridView.showTooltips
            hideLabel: gridView.hideLabelsOnFavorites && gridView.favoritesActive
            isCurrentItem: gridView.currentIndex === model.index
            iconSize: gridView.iconSize
            isNew: gridView.showNewAppBadge && gridView.appsModel ? gridView.appsModel.isNewApp(model.storageId || "") : false
            editMode: gridView.editMode
            isSelected: gridView.editMode && gridView.selectedSwapIndex === model.index
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    gridView.contextMenuRequested(model.index, model.storageId || "", model.desktopFile || "")
                    return
                }
                if (gridView.editMode) {
                    if (gridView.selectedSwapIndex < 0) {
                        // First click: select this icon
                        gridView.selectedSwapIndex = model.index
                    } else if (gridView.selectedSwapIndex === model.index) {
                        // Click selected again: deselect
                        gridView.selectedSwapIndex = -1
                    } else {
                        // Click a different icon: swap positions
                        var fromIndex = gridView.selectedSwapIndex
                        gridView.selectedSwapIndex = -1
                        var selectedData = gridView.appsModel.get(fromIndex)
                        if (selectedData && gridView.appsModel) {
                            gridView.appsModel.moveFavorite(selectedData.storageId, model.index)
                            gridView.favoritesOrderChanged()
                        }
                    }
                } else {
                    gridView.launched(model.index)
                }
            }
            onShuffleRequested: gridView.shuffleIcon(model.index)
            onRemoveRequested: {
                if (gridView.appsModel) {
                    gridView.appsModel.toggleFavorite(model.storageId || "")
                    gridView.favoritesOrderChanged()
                    if (gridView.selectedSwapIndex === model.index)
                        gridView.selectedSwapIndex = -1
                }
            }
        }

        Connections {
            target: gridView
            function onShakeAllIcons() { iconDelegate.shake() }
            function onShufflesUpdated() {
                iconDelegate.displayIcon = gridView.getDisplayIcon(model.index)
            }
        }
    }
}
