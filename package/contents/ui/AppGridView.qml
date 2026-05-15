/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Icon grid view for applications with hover shake animation.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

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

    clip: true
    // Cache buffer: extra screens of delegates kept alive off-screen. Grown
    // while a drag is in flight so an auto-scroll cannot recycle the source
    // delegate (which would drop the pointer grab). One viewport of slack
    // is enough — the row count of favorites that fit in a viewport is the
    // upper bound on how far auto-scroll moves before the user lifts.
    cacheBuffer: (favoritesDragProxy && favoritesDragProxy.Drag.active)
                 ? Math.max(height, Kirigami.Units.gridUnit * 16)
                 : Kirigami.Units.gridUnit * 4
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
    property var sharedFavoritesModel: null
    // Shared drag proxy from the plasmoid root; set by GridPanel.
    property var favoritesDragProxy: null

    // FavoriteId role index — pushed in by the owner once the shared model
    // is ready (see GridPanel.sharedFavoritesLoader). -1 disables lookup.
    property int _favoriteIdRole: -1

    function _findFavoriteRow(storageId) {
        if (!sharedFavoritesModel || _favoriteIdRole < 0) return -1
        const prefixed = "applications:" + storageId
        for (let i = 0; i < sharedFavoritesModel.count; ++i) {
            const v = sharedFavoritesModel.data(sharedFavoritesModel.index(i, 0), _favoriteIdRole)
            if (v === storageId || v === prefixed) return i
        }
        return -1
    }
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

    function _launchCurrent() {
        if (recentIndex >= 0) {
            launchRecentByIndex(recentIndex)
            return
        }
        if (currentIndex < 0) return
        // In favorites view the grid is bound to KAStats directly, so the
        // current index is a favorites row, not a proxy row. Resolve to a
        // storageId and launch via the shared launch path.
        if (favoritesActive && sharedFavoritesModel
                && model === sharedFavoritesModel) {
            const v = sharedFavoritesModel.data(
                sharedFavoritesModel.index(currentIndex, 0), _favoriteIdRole)
            const sid = (v && v.indexOf && v.indexOf("applications:") === 0)
                        ? v.substring(13) : (v || "")
            if (sid) recentLaunched(sid)
        } else {
            launched(currentIndex)
        }
    }
    Keys.onReturnPressed: _launchCurrent()
    Keys.onEnterPressed: _launchCurrent()
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

        // When favoritesActive, the grid is driven directly by
        // sharedFavoritesModel (KAStats), which exposes different role names
        // than AppFilterModel. Resolve the storage id from the model and
        // look up the matching AppModel row for non-essential fields
        // (genericName, comment, installSource, desktopFile, isNew).
        readonly property bool _fromShared: gridView.favoritesActive
                                            && gridView.sharedFavoritesModel
                                            && gridView.model === gridView.sharedFavoritesModel
        readonly property string _sid: _fromShared
            ? ((model.favoriteId || "").indexOf("applications:") === 0
                ? model.favoriteId.substring(13) : (model.favoriteId || ""))
            : (model.storageId || "")
        readonly property var _appData: _fromShared && gridView.appsModel
                                        ? gridView.appsModel.getByStorageId(_sid) : null

        AppIconDelegate {
            id: iconDelegate
            anchors.fill: parent
            appName: delegateRoot._fromShared
                ? (model.display || (delegateRoot._appData ? delegateRoot._appData.name : "") || "")
                : (model.name || "")
            appIcon: delegateRoot._fromShared
                ? ((delegateRoot._appData && delegateRoot._appData.iconName)
                   || model.decoration || "application-x-executable")
                : (model.iconName || "application-x-executable")
            displayIcon: delegateRoot._fromShared ? "" : gridView.getDisplayIcon(model.index)
            appGenericName: delegateRoot._fromShared
                ? (delegateRoot._appData ? delegateRoot._appData.genericName || "" : "")
                : (model.genericName || "")
            appComment: delegateRoot._fromShared
                ? (delegateRoot._appData ? delegateRoot._appData.comment || "" : "")
                : (model.comment || "")
            installSource: delegateRoot._fromShared
                ? (delegateRoot._appData ? delegateRoot._appData.installSource || "" : "")
                : (model.installSource || "")
            showTooltip: gridView.showTooltips
            hideLabel: gridView.hideLabelsOnFavorites && gridView.favoritesActive
            isCurrentItem: gridView.currentIndex === model.index
            iconSize: gridView.iconSize
            isNew: !delegateRoot._fromShared
                   && gridView.showNewAppBadge && gridView.appsModel
                   ? gridView.appsModel.isNewApp(delegateRoot._sid) : false
            storageId: delegateRoot._sid
            gridRow: model.index
            // Drag is only available on the favorites tab; manual-ordering
            // is incompatible with the alphabetical-sort option.
            dragProxy: (gridView.favoritesActive
                        && gridView.sharedFavoritesModel
                        && !Plasmoid.configuration.sortFavoritesAlphabetically)
                       ? gridView.favoritesDragProxy : null
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    const desktopFile = delegateRoot._fromShared
                        ? (delegateRoot._appData ? delegateRoot._appData.desktopFile || "" : "")
                        : (model.desktopFile || "")
                    gridView.contextMenuRequested(model.index, delegateRoot._sid, desktopFile)
                    return
                }
                if (delegateRoot._fromShared) {
                    if (delegateRoot._sid) gridView.recentLaunched(delegateRoot._sid)
                } else {
                    gridView.launched(model.index)
                }
            }
            onShuffleRequested: {
                if (!delegateRoot._fromShared)
                    gridView.shuffleIcon(model.index)
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

    // -- Drag reorder handler --
    // Sits behind the delegates (z below them so clicks still reach icons)
    // and reacts to drag positions originating from the shared favorites
    // drag proxy. We rewrite the KAStats favorites order on every cursor
    // movement; the grid's `move`/`moveDisplaced` transitions provide the
    // animated reflow. If the drop ends outside, we replay the move log
    // in reverse so the user sees no net change.
    DropArea {
        id: reorderArea
        parent: gridView
        anchors.fill: parent
        z: -1
        enabled: gridView.favoritesActive
                 && gridView.sharedFavoritesModel
                 && !Plasmoid.configuration.sortFavoritesAlphabetically

        property var pendingMoves: []

        onEntered: drag => { pendingMoves = [] }

        onExited: {
            // Undo every move when leaving the area without dropping
            while (pendingMoves.length > 0) {
                const [from, to] = pendingMoves.pop()
                gridView.sharedFavoritesModel.moveRow(to, from)
            }
        }

        onPositionChanged: drag => {
            if (!gridView.favoritesDragProxy
                    || drag.source !== gridView.favoritesDragProxy
                    || !gridView.favoritesDragProxy.sourceItem
                    || !gridView.sharedFavoritesModel) {
                return
            }
            // Hold off on reorder while existing animations or auto-scroll
            // are still settling. Subsequent positionChanged events as the
            // pointer moves will retry.
            if (gridView.move.running || gridView.moveDisplaced.running
                    || gridView.flicking || gridView.moving
                    || scrollUp.running || scrollDown.running) {
                drag.accept(Qt.MoveAction)
                return
            }

            const source = gridView.favoritesDragProxy.sourceItem
            // Re-resolve the source's current row from the model rather than
            // trusting the cached value — content may have shifted under us
            // during a scroll or external favorites change.
            const liveSourceRow = gridView._findFavoriteRow(source.storageId)
            if (liveSourceRow < 0) return
            source.gridRow = liveSourceRow

            const pos = mapToItem(gridView.contentItem, drag.x, drag.y)
            const target = gridView.indexAt(pos.x, pos.y)
            if (target < 0 || target === liveSourceRow) {
                drag.accept(Qt.MoveAction)
                return
            }

            gridView.sharedFavoritesModel.moveRow(liveSourceRow, target)
            pendingMoves.push([liveSourceRow, target])
            source.gridRow = target
            drag.accept(Qt.MoveAction)
        }

        onDropped: drag => {
            // Drop accepted — keep current order. KAStats persists itself.
            pendingMoves = []
        }
    }

    // Edge auto-scroll while dragging — proximity-driven. Closer to the
    // viewport edge means faster scroll; eases in smoothly as the pointer
    // crosses the zone boundary.
    readonly property real _scrollEdge: Kirigami.Units.gridUnit * 2
    readonly property real _scrollMinPxPerTick: 1
    readonly property real _scrollMaxPxPerTick: Kirigami.Units.gridUnit * 0.6
    readonly property real _scrollIntervalMs: 16 // ~60 Hz

    // Two pseudo-states keep the parameters readable.
    readonly property bool _scrollingUp: reorderArea.enabled
        && reorderArea.containsDrag
        && reorderArea.drag.y >= 0
        && reorderArea.drag.y < _scrollEdge
        && gridView.contentY > 0
    readonly property bool _scrollingDown: reorderArea.enabled
        && reorderArea.containsDrag
        && reorderArea.drag.y > gridView.height - _scrollEdge
        && reorderArea.drag.y <= gridView.height
        && gridView.contentY < (gridView.contentHeight - gridView.height)

    Timer {
        id: edgeScrollTimer
        interval: gridView._scrollIntervalMs
        repeat: true
        running: gridView._scrollingUp || gridView._scrollingDown
        onTriggered: {
            // Distance from the edge, clamped to the zone size.
            const y = reorderArea.drag.y
            const inside = gridView._scrollingUp
                ? (gridView._scrollEdge - Math.max(0, y))
                : (y - (gridView.height - gridView._scrollEdge))
            const t = Math.max(0, Math.min(1, inside / gridView._scrollEdge))
            // Quadratic easing — gentle near the boundary, snappier near edge.
            const delta = gridView._scrollMinPxPerTick
                + (gridView._scrollMaxPxPerTick - gridView._scrollMinPxPerTick) * t * t
            const dir = gridView._scrollingUp ? -1 : 1
            const next = gridView.contentY + dir * delta
            const max = Math.max(0, gridView.contentHeight - gridView.height)
            gridView.contentY = Math.max(0, Math.min(max, next))
        }
    }

    // Shims kept so the reorder code can still query "is a scroll in progress".
    QtObject {
        id: scrollUp
        readonly property bool running: gridView._scrollingUp
    }
    QtObject {
        id: scrollDown
        readonly property bool running: gridView._scrollingDown
    }
}
