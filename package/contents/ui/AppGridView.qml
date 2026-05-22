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
import "favoriteid.js" as FavoriteId

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
    cacheBuffer: (dragSource && dragSource.isDragInFlight)
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
    // Shared DragSource from the plasmoid root; set by GridPanel.
    property DragSource dragSource: null

    // FavoriteId role index — pushed in by the owner once the shared model
    // is ready (see GridPanel.sharedFavoritesLoader). -1 disables lookup.
    property int favoriteIdRole: -1

    function findFavoriteRow(storageId) {
        if (!sharedFavoritesModel || favoriteIdRole < 0) return -1
        const prefixed = FavoriteId.toPrefixed(storageId)
        for (let i = 0; i < sharedFavoritesModel.count; ++i) {
            const v = sharedFavoritesModel.data(sharedFavoritesModel.index(i, 0), favoriteIdRole)
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

    // -- Multi-select --
    // Enabled in Favorites view (drives reorder/remove flows against
    // KAStats) and in All / category-filtered view (drag-out + add to
    // favorites). Source of truth lives on the SelectionState child; the
    // accessors below preserve the older AppGridView API so consumers
    // (GridPanel, KeyboardShortcuts, the delegate) keep working unchanged.
    SelectionState {
        id: selection
        sidAt: function(idx) { return gridView._sidAt(idx) }
        gridCount: gridView.count
    }
    readonly property bool _favoritesSelect: favoritesActive
                                             && sharedFavoritesModel
                                             && model === sharedFavoritesModel
    readonly property bool _otherSelect: !favoritesActive
                                         && appsModel
                                         && model === appsModel
    readonly property bool multiSelectActive: _favoritesSelect || _otherSelect

    property alias selectedSids: selection.selectionSids
    property alias selectionAnchor: selection.anchor
    readonly property alias selectionCount: selection.selectionCount

    function selectionContainsSid(sid) { return selection.contains(sid) }
    function selectedSidList() { return selection.sidList() }

    function _sidAt(idx) {
        if (!multiSelectActive || idx < 0 || idx >= count) return ""
        if (_favoritesSelect) {
            const v = sharedFavoritesModel.data(
                sharedFavoritesModel.index(idx, 0), favoriteIdRole)
            return FavoriteId.stripPrefix(v) || ""
        }
        // Proxy-model path (All / category-filtered view): AppFilterModel
        // exposes storageId as a role; appsModel.get(idx) yields the row.
        const row = appsModel ? appsModel.get(idx) : null
        return row && row.storageId ? row.storageId : ""
    }

    function toggleSelectionAt(idx) {
        if (multiSelectActive) selection.toggleAt(idx)
    }
    function toggleSelectionBySid(sid) {
        if (multiSelectActive) selection.toggleSid(sid, -1)
    }
    function rangeSelectTo(idx) {
        if (multiSelectActive) selection.rangeTo(idx)
    }
    function selectAllVisible() {
        if (multiSelectActive) selection.selectAll(currentIndex)
    }
    function clearSelection() { selection.clear() }
    function selectedDesktopFileUrls() { return selection.desktopFileUrls(appsModel) }
    function selectedIconNames() { return selection.iconNames(appsModel) }

    function removeSelectedFromFavorites() {
        if (!_favoritesSelect || selectionCount === 0) return
        const sids = selectedSidList()
        for (var i = 0; i < sids.length; ++i)
            sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(sids[i]))
        clearSelection()
    }

    // Drop selection whenever the favorites tab is left or the underlying
    // model changes. Keeps state scoped to the active view and prevents
    // ghost selections from re-appearing after a tab toggle.
    onFavoritesActiveChanged: clearSelection()
    onModelChanged: clearSelection()

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
                sharedFavoritesModel.index(currentIndex, 0), favoriteIdRole)
            const sid = FavoriteId.stripPrefix(v)
            if (sid) recentLaunched(sid)
        } else {
            launched(currentIndex)
        }
    }
    Keys.onReturnPressed: { _launchCurrent(); clearSelection() }
    Keys.onEnterPressed: { _launchCurrent(); clearSelection() }

    // Shift+Arrow extends the multi-selection from the anchor through the
    // new current index. Plain arrows clear selection so anchor state never
    // drifts behind the visible cursor. Routed through SelectionState so
    // the behaviour matches CategoryGridView byte-for-byte.
    function _arrowMoveWithSelection(event, moveFn) {
        if (multiSelectActive)
            selection.extendOrMove(event, moveFn, function() { return currentIndex })
        else
            moveFn()
    }

    Keys.onUpPressed: function(event) {
        if (recentIndex >= 0) {
            var newIdx = recentIndex - effectiveColumns
            if (newIdx >= 0) {
                recentIndex = newIdx
            } else {
                recentIndex = -1
                currentIndex = -1
                if (searchField) searchField.forceActiveFocus()
            }
        } else if (currentIndex >= 0 && currentIndex < effectiveColumns && showRecents) {
            var lastRow = Math.floor((recentCount - 1) / effectiveColumns)
            recentIndex = Math.min(currentIndex + lastRow * effectiveColumns, recentCount - 1)
            currentIndex = -1
        } else {
            _arrowMoveWithSelection(event, moveCurrentIndexUp)
        }
    }
    Keys.onDownPressed: function(event) {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + effectiveColumns
            if (newIdx < recentCount) {
                recentIndex = newIdx
            } else {
                currentIndex = Math.min(recentIndex % effectiveColumns, count - 1)
                recentIndex = -1
            }
        } else {
            _arrowMoveWithSelection(event, moveCurrentIndexDown)
        }
    }
    Keys.onLeftPressed: function(event) {
        // Alt+Left belongs to the category bar — let it bubble up.
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        if (recentIndex > 0)
            recentIndex--
        else if (recentIndex < 0)
            _arrowMoveWithSelection(event, moveCurrentIndexLeft)
    }
    Keys.onRightPressed: function(event) {
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        if (recentIndex >= 0 && recentIndex < recentCount - 1)
            recentIndex++
        else if (recentIndex < 0)
            _arrowMoveWithSelection(event, moveCurrentIndexRight)
    }

    // Esc clears multi-selection first; only when there's no selection do
    // we let the event bubble (the popup window closes on bare Esc).
    Keys.onEscapePressed: function(event) {
        if (selection.consumeEscape()) event.accepted = true
    }
    // Consume Tab to prevent it from reaching the focus chain or search bar
    Keys.onTabPressed: function(event) { event.accepted = true }
    Keys.onBacktabPressed: function(event) { event.accepted = true }

    KeyboardShortcuts { gridView: gridView }

    Keys.onPressed: function(event) {
        // Redirect typing to search bar, but not Tab or special keys
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return
        // Space toggles selection on the focused item (Favorites only).
        // Caught here rather than in Keys.onSpacePressed because there's no
        // dedicated handler for it; Space's printable " " would otherwise
        // fall through to the search-bar redirect below.
        if (event.key === Qt.Key_Space && multiSelectActive
                && currentIndex >= 0 && recentIndex < 0) {
            toggleSelectionAt(currentIndex)
            event.accepted = true
            return
        }
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
        dragSource: gridView.dragSource
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
            ? FavoriteId.stripPrefix(model.favoriteId)
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
            desktopFile: delegateRoot._fromShared
                ? (delegateRoot._appData ? delegateRoot._appData.desktopFile || "" : "")
                : (model.desktopFile || "")
            gridRow: model.index
            // Drag-out is allowed from every view (taskbar/panel/Dolphin
            // pinning); internal reorder is gated separately in the DropArea
            // based on the source delegate's storageId lookup, so always
            // wiring the proxy here is safe.
            dragSource: gridView.dragSource

            // Selection visuals — `selected` reads the GridView's selection
            // map, so toggling any item re-evaluates the binding for all
            // delegates in one pass. `selectionAnchor` highlights the pivot
            // item used by Shift+click / Shift+Arrow range select.
            selected: gridView.multiSelectActive
                      && !!gridView.selectedSids[delegateRoot._sid]
            selectionAnchor: gridView.multiSelectActive
                             && gridView.selectionAnchor === model.index
                             && gridView.selectionCount > 0
            // Carry the full multi-selection bundle so dragging this item
            // initiates a multi-URI drag-out. Only populated when this
            // delegate is itself selected.
            multiSelectionSids: selected ? gridView.selectedSidList() : []
            multiSelectionUrls: selected ? gridView.selectedDesktopFileUrls() : []
            multiSelectionIcons: selected ? gridView.selectedIconNames() : []

            onClicked: function(mouse) {
                const desktopFile = delegateRoot._fromShared
                    ? (delegateRoot._appData ? delegateRoot._appData.desktopFile || "" : "")
                    : (model.desktopFile || "")
                if (mouse.button === Qt.RightButton) {
                    // Selection persists across right-click so the menu can
                    // surface "Add to selection" / "Remove from selection".
                    gridView.contextMenuRequested(model.index, delegateRoot._sid, desktopFile)
                    return
                }
                if (gridView.multiSelectActive) {
                    gridView.currentIndex = model.index
                    if (selection.applyModClick(mouse, model.index)) return
                }
                gridView.clearSelection()
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

    FavoritesReorderArea {
        id: reorderArea
        parent: gridView
        gridView: gridView
        edgeScroller: edgeScroller
    }

    EdgeAutoScroller {
        id: edgeScroller
        flickable: gridView
        dropArea: reorderArea
    }
}
