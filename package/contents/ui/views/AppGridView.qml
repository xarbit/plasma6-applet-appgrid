/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Icon grid view for applications with hover shake animation.
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import dev.xarbit.appgrid.models

import "../controllers"
import "../widgets"
import "../js/favoriteid.js" as FavoriteId
import "../js/favoritetoggle.js" as FavoriteToggle
import "../js/favoritevisual.js" as FavoriteVisual
import "../js/gridmetrics.js" as GridMetrics
import "../js/constants.js" as Const

GridView {
    id: gridView

    // The panel this grid lives in (GridHost): the models and objects it reads,
    // and where its launches and menus go.
    required property GridHost host

    // Number of columns to display. If adaptiveColumns is true, computed from width.
    property int columns: host.columns
    property bool adaptiveColumns: false
    readonly property int effectiveColumns: adaptiveColumns
        ? GridMetrics.columnsForWidth(width, GridMetrics.labelledCellWidth(
            cellStyle.iconSize, Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing,
            cellStyle.fontScale, cellStyle.reduceGridSpacing), 3)
        : columns

    // How the cells draw (CellStyle). Its icon size and label scale also set
    // the cell size, so cells stay proportional across the size presets.
    readonly property CellStyle cellStyle: host.cellStyle
    PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: gridView.cellStyle.showScrollbars }

    // Disables Ctrl+Shift+Arrow favorite reordering (KAStats can't persist a
    // manual order while alphabetical sort is on). Injected from the boundary.
    required property bool sortFavoritesAlphabetically

    // Emitted when a shake-all-icons trigger fires (e.g. on grid open).
    signal shakeAllIcons()

    signal openFolderRequested(string folderId)
    signal folderContextMenuRequested(string folderId)
    signal emptyAreaContextMenuRequested()

    // Right-click on empty space in the folder grid → create-folder menu. Gated
    // on there being no cell under the cursor, so right-clicking an icon or
    // folder (which raise their own menus) doesn't also fire this (#18).
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => {
            // Create-folder on empty space: favourites-editable, and only at the
            // top level — no nesting inside an open folder (#18).
            if (!gridView._groupedGrid || !gridView.groupEditable
                    || gridView.groupedModel.canGoBack)
                return
            // Map the scene point into the content item and ask what's there —
            // a delegate under the cursor (icon/folder) raises its own menu, so
            // only a hit on bare content opens the create-folder menu.
            const p = gridView.contentItem.mapFromItem(null,
                eventPoint.scenePosition.x, eventPoint.scenePosition.y)
            if (!gridView.contentItem.childAt(p.x, p.y))
                gridView.emptyAreaContextMenuRequested()
        }
    }

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

        var fromPos = fromItem.mapToItem(shuffleOverlayParent, fromItem.width / 2 - gridView.cellStyle.iconSize / 2, 0)
        var otherPos = otherItem.mapToItem(shuffleOverlayParent, otherItem.width / 2 - gridView.cellStyle.iconSize / 2, 0)

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

    // Back to the just-opened state: top of the grid, nothing selected or
    // current, no shuffles. The model may still refill after this and move
    // originY, so the first such move scrolls to the top again.
    property bool _scrollToTopPending: false
    function resetView() {
        clearShuffles()
        selection.clear()
        contentY = originY
        currentIndex = -1
        recentIndex = -1
        _scrollToTopPending = true
    }
    onOriginYChanged: {
        if (_scrollToTopPending) {
            contentY = originY
            _scrollToTopPending = false
        }
    }

    readonly property string defaultIcon: Const.DEFAULT_ICON

    // Drag-to-folder fold target (#200): the central fraction of the icon/folder
    // tile that arms an add. The cursor must land inside this inset square; the
    // rest of the cell reorders. One value so the app icon and folder tile match.
    readonly property real foldZoneInset: 0.20

    function getDisplayIcon(index) {
        return iconSwaps[index] !== undefined ? iconSwaps[index] : ""
    }

    function resolveIcon(index, fallbackName) {
        if (iconSwaps[index] !== undefined) return iconSwaps[index]
        return fallbackName || defaultIcon
    }

    clip: true

    WheelScroller { target: gridView }

    // Cache buffer: a viewport of delegates kept alive off-screen. Builds the
    // next rows ahead of the scroll so they aren't constructed on-frame (the main
    // scroll-smoothness lever now that delegates aren't recycled). The viewport
    // of slack also keeps a drag's source delegate alive through auto-scroll, so
    // the pointer grab isn't dropped.
    cacheBuffer: Math.max(height, Kirigami.Units.gridUnit * 16)
    readonly property bool labelsHidden: hideLabelsOnFavorites && favoritesActive
    cellWidth: Math.floor(width / effectiveColumns)
    cellHeight: labelsHidden
               ? cellWidth
               : GridMetrics.labelledCellHeight(cellStyle.iconSize, Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, cellStyle.fontScale)
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: true
    currentIndex: -1
    highlightFollowsCurrentItem: true
    // Snapped (no slide) while _snapHighlight — used when a drill view re-selects
    // the folder just left on going back, so the highlight lands on it, not slides.
    highlightMoveDuration: (cellStyle.animateHighlight && !_snapHighlight) ? Kirigami.Units.shortDuration : 0
    property bool _snapHighlight: false
    // Set currentIndex without animating the highlight there.
    function selectSnapped(idx) {
        _snapHighlight = true
        currentIndex = idx
        Qt.callLater(function() { gridView._snapHighlight = false })
    }

    // Smooth transitions when items move during drag reorder
    move: Transition {
        NumberAnimation { properties: "x,y"; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }
    moveDisplaced: Transition {
        NumberAnimation { properties: "x,y"; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    // Search field to return focus to when typing text
    readonly property Item searchField: host.searchField
    // The apps model for section queries
    readonly property var appsModel: host.appsModel
    // Single source of truth for favourites (controllers/FavoritesManager):
    // the mutations, and the models read below.
    readonly property var favoritesManager: host.favoritesManager
    readonly property var sharedFavoritesModel: favoritesManager ? favoritesManager.sharedFavoritesModel : null
    // C++ grouped model (issue #18). When the grid is bound to it, favourite app
    // rows still resolve via favoriteId (like KAStats), and folder rows render a
    // FolderCell that opens on click.
    readonly property var favoritesGroupedModel: favoritesManager ? favoritesManager.favoritesGroupedModel : null
    // The favourites model's FavoriteId role; -1 without one.
    readonly property int favoriteIdRole: favoritesManager ? favoritesManager.favoriteIdRole : -1
    // The grouped model this grid renders when `model` is bound to it — the
    // favourites folders (favoritesGroupedModel) or the read-only menu tree
    // (#201). Both expose the AbstractGroupedModel row API, so the delegate and
    // selection treat them identically; only mutation differs (groupEditable).
    property var groupedModel: null
    // Favourites grouping is editable (reorder, drag-to-folder, create folder);
    // the menu tree is read-only. Gates those mutations.
    property bool groupEditable: true
    // Shared DragSource from the plasmoid root.
    readonly property DragSource dragSource: host.dragSource

    // Name + icon for a favourite that has no row in the app model (a System
    // Settings module favourited via #64), read from KAStats. The grouped model
    // can't carry the KAStats QIcon, so the grouped grid resolves it here.
    function _favoriteVisual(sid) {
        const v = FavoriteVisual.resolve(appsModel, sharedFavoritesModel, favoriteIdRole, sid, defaultIcon)
        return { display: v.name, decoration: v.icon }
    }

    function findFavoriteRow(storageId) {
        return sharedFavoritesModel ? sharedFavoritesModel.rowOfFavoriteId(storageId) : -1
    }
    // Config toggles
    property bool showRecentApps: true
    property bool startWithFavorites: false
    property bool favoritesActive: false
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
        if (appsModel.sortMode === AppFilterModel.MostUsed)
            return false

        return !favoritesActive
    }

    // Keyboard navigation index for recent items in header (-1 = not in recents)
    property int recentIndex: -1
    readonly property int recentCount: showRecents ? appsModel.recentApps.length : 0

    // -- Multi-select --
    // Multi-selection, enabled in the Favorites view (reorder/remove against
    // KAStats) and in the All / category-filtered view (drag-out + add to
    // favorites). Spans the recents row and the grid (see GridSelection).
    GridSelection {
        id: gridSelection
        active: gridView.multiSelectActive
        appsModel: gridView.appsModel
        recentCount: gridView.recentCount
        itemCount: gridView.count
        recentIndex: gridView.recentIndex
        currentIndex: gridView.currentIndex
        gridSidAt: function(index) { return gridView._sidAt(index) }
    }
    readonly property alias selection: gridSelection

    // The favourites grid drives selection whether it is the direct KAStats grid
    // or the grouped (folders) grid — both key selection by storageId.
    // The grid is bound to a grouped model (favourites folders or the menu tree).
    readonly property bool _groupedGrid: !!groupedModel && model === groupedModel
    readonly property bool _favoritesSelect: favoritesActive
                                             && ((sharedFavoritesModel && model === sharedFavoritesModel)
                                                 || _groupedGrid)
    readonly property bool _otherSelect: !favoritesActive
                                         && appsModel
                                         && model === appsModel
    // Any grouped grid is selectable too (favourites: reorder/remove; menu:
    // drag-out / add-to-favourites).
    readonly property bool multiSelectActive: _favoritesSelect || _otherSelect || _groupedGrid

    // Row of the folder @p folderId in the current grouped level (0 if absent) —
    // used to re-select the folder just left when a drill view goes back a level.
    function rowOfFolder(folderId) {
        return _groupedGrid ? Math.max(0, groupedModel.indexOfFolder(folderId)) : 0
    }

    function _sidAt(idx) {
        if (!multiSelectActive || idx < 0 || idx >= count) return ""
        if (_groupedGrid) {
            // Folders aren't selectable.
            if (groupedModel.entryTypeAt(idx) === AbstractGroupedModel.Folder) return ""
            return FavoriteId.stripPrefix(groupedModel.favoriteIdAt(idx)) || ""
        }
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

    function removeSelectedFromFavorites() {
        if (!_favoritesSelect || selection.selectionCount === 0 || !favoritesManager) return
        const sids = selection.sidList()
        for (var i = 0; i < sids.length; ++i)
            favoritesManager.removeFavorite(sids[i])
        selection.clear()
    }

    // Ctrl+D (#193): browser-style toggle of the selected apps, or the single
    // highlighted one when nothing is multi-selected. Works in every view (All,
    // category, recents, favourites) — `selection.sidAt` resolves the row to a
    // storageId, returning "" for folders so they're skipped. Add-all-if-any-
    // missing, else remove-all, so a mixed selection has one predictable result.
    function toggleFavoritesForSelectionOrCurrent() {
        if (!favoritesManager) return
        const sids = selection.selectionCount > 0 ? selection.sidList()
                                                  : [selection.sidAt(selection.virtualIndex)]
        const entries = sids.map(s => ({ sid: s, isFavorite: favoritesManager.isFavorite(s) }))
        const plan = FavoriteToggle.plan(entries)
        for (const s of plan.add)
            favoritesManager.addFavorite(s)
        for (const s of plan.remove)
            favoritesManager.removeFavorite(s)
        _bounceSids(plan.add.concat(plan.remove))
        selection.clear()
    }

    // Bounce every currently-visible delegate whose app was just toggled. One
    // pass over the grid; off-screen rows return null from itemAtIndex and are
    // skipped (a removed favourite in the favourites view simply isn't there).
    function _bounceSids(sids) {
        if (!sids || sids.length === 0) return
        const want = {}
        for (const s of sids) if (s) want[s] = true
        for (let i = 0; i < count; ++i) {
            const it = itemAtIndex(i)
            if (it && want[it._sid])
                it.bounceFeedback()
        }
    }

    // Drop selection whenever the favorites tab is left or the underlying
    // model changes. Keeps state scoped to the active view and prevents
    // ghost selections from re-appearing after a tab toggle.
    onFavoritesActiveChanged: selection.clear()
    onModelChanged: selection.clear()

    function launchRecentByIndex(idx) {
        if (idx >= 0 && idx < recentCount)
            host.launchRequested(appsModel.recentApps[idx])
    }

    // Launch the favourite @p sid (its bare id: an app, a jump-list action, a
    // System Settings module or a document). The launch service resolves any of
    // them and records an app launch, wherever it came from.
    function launchFavorite(sid) {
        if (sid)
            host.launchRequested(sid)
    }

    function _launchCurrent() {
        if (recentIndex >= 0) {
            launchRecentByIndex(recentIndex)
            return
        }
        if (currentIndex < 0) return
        // A grouped grid (favourites, menu tree) holds ids, not app rows: open a
        // folder, launch an entry by its id.
        if (_groupedGrid) {
            if (groupedModel.entryTypeAt(currentIndex) === AbstractGroupedModel.Folder) {
                openFolderRequested(groupedModel.folderIdAt(currentIndex))
            } else {
                launchFavorite(FavoriteId.stripPrefix(groupedModel.favoriteIdAt(currentIndex)))
            }
        } else {
            host.launchAppRequested(currentIndex)
        }
    }
    function activateCurrent() {
        selection.activate(sids => host.bulkLaunchRequested(sids), _launchCurrent)
    }
    Keys.onReturnPressed: activateCurrent()
    Keys.onEnterPressed: activateCurrent()

    // Enter the grid from the search field (Down / Tab): focus it and select
    // its first entry, the recents row's when it shows.
    function enterFromSearch() {
        forceActiveFocus()
        if (showRecents) {
            recentIndex = 0
            currentIndex = -1
        } else {
            currentIndex = count > 0 ? 0 : -1
        }
    }

    function _exitToSearchField() {
        recentIndex = -1
        currentIndex = -1
        if (searchField) searchField.forceActiveFocus()
    }

    GridKeyboardNav {
        id: keyNav
        searchField: gridView.searchField
        recentIndex: gridView.recentIndex
        gridIndex: gridView.currentIndex
        recentCount: gridView.recentCount
        gridCount: gridView.count
        columns: gridView.effectiveColumns
        mirrored: gridView.effectiveLayoutDirection === Qt.RightToLeft
        selection: gridView.selection
        selectionActive: gridView.multiSelectActive
        onCategoryNavRequested: direction => gridView.host.categoryNavRequested(direction)
        onCursorRequested: (recent, grid) => {
            gridView.currentIndex = grid
            gridView.recentIndex = recent
        }
        onExitRequested: gridView._exitToSearchField()
    }
    Keys.onUpPressed: event => keyNav.handleArrow(event)
    Keys.onDownPressed: event => keyNav.handleArrow(event)
    Keys.onLeftPressed: event => keyNav.handleArrow(event)
    Keys.onRightPressed: event => keyNav.handleArrow(event)

    // Esc clears multi-selection first. With no selection, hand off to the host
    // (e.g. the menu drill view goes back a level); if the host doesn't act, the
    // event is left unaccepted so the window Shortcut can close the launcher.
    signal escapePressed()
    Keys.onEscapePressed: function(event) {
        if (selection.consumeEscape()) {
            event.accepted = true
            return
        }
        gridView.escapePressed()
    }
    // Consume Tab to prevent it from reaching the focus chain or search bar
    Keys.onTabPressed: function(event) { event.accepted = true }
    Keys.onBacktabPressed: function(event) { event.accepted = true }

    KeyboardShortcuts {
        gridView: gridView
        sortFavoritesAlphabetically: gridView.sortFavoritesAlphabetically
    }

    // Bumped on newAppsChanged so each cell's isNew binding re-evaluates (a
    // launch clears the new-app badge) without a Connections object per delegate.
    property int _newAppsRevision: 0
    Connections {
        target: gridView.appsModel
        function onNewAppsChanged() { gridView._newAppsRevision++ }
    }

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
            selection.toggleSelectionAt(currentIndex)
            event.accepted = true
            return
        }
        if (keyNav.forwardTyping(event)) {
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
        cellStyle: gridView.cellStyle
        currentRecentIndex: gridView.recentIndex
        gridHasFocus: gridView.activeFocus
        favoritesActive: gridView.favoritesActive
        dragSource: gridView.dragSource
        multiSelectActive: gridView.multiSelectActive
        selectionSids: gridView.selection.selectionSids
        multiSelectionUrls: gridView.selection.selectedDesktopFileUrls()
        multiSelectionIcons: gridView.selection.selectedIconNames()
        onRecentLaunched: function(storageId) { gridView.host.launchRequested(storageId) }
        onContextMenuRequested: function(storageId, desktopFile) {
            gridView.host.appMenuRequested(storageId, desktopFile, gridView.selection.sidList())
        }
        tryModifierClick: function(recentIdx, mouse) {
            if (!gridView.selection.applyRecentClickModifiers(mouse, recentIdx)) return false
            gridView.recentIndex = recentIdx
            gridView.currentIndex = -1
            gridView.forceActiveFocus()
            return true
        }

        Connections {
            target: gridView
            function onShakeAllIcons() { gridView.headerItem.shakeAll() }
        }
    }

    highlight: Item {
        GridHighlight {
            cellWidth: gridView.cellWidth
            cellHeight: gridView.cellHeight
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
        // Grid bound to the grouped model (issue #18): folder rows render a
        // FolderCell, app rows resolve via favoriteId exactly like the direct
        // KAStats grid does.
        readonly property bool _fromGrouped: gridView._groupedGrid
        readonly property bool _isFolder: _fromGrouped && model.entryType === AbstractGroupedModel.Folder
        // "Shared" = a favourite app row keyed by favoriteId — true for both the
        // direct KAStats grid and the grouped model's app rows.
        readonly property bool _fromShared: (gridView.favoritesActive
                                             && gridView.sharedFavoritesModel
                                             && gridView.model === gridView.sharedFavoritesModel)
                                            || (_fromGrouped && !_isFolder)
        readonly property string _sid: _isFolder
            ? ""
            : (_fromShared ? FavoriteId.stripPrefix(model.favoriteId) : (model.storageId || ""))
        // Drag-to-folder target zone (#200): the folder's tile or the app's icon,
        // inset a little so it's a tighter target and more of the cell reorders.
        // Landing on it merges/adds; a drag can still pass over a folder.
        readonly property rect foldRect: {
            const r = (_isFolder && folderLoader.item) ? folderLoader.item.iconRect : iconDelegate.iconRect
            const m = r.width * gridView.foldZoneInset
            return Qt.rect(r.x + m, r.y + m, r.width - 2 * m, r.height - 2 * m)
        }
        readonly property var _appData: _fromShared && gridView.appsModel
                                        ? gridView.appsModel.getByStorageId(_sid) : null
        // getByStorageId returns {} (not null) for an id the app model doesn't
        // know, so test the icon, not the object.
        readonly property bool _appKnown: !!(_appData && _appData.iconName)
        // KAStats name/icon fallback for a grouped app row the app model doesn't
        // know (a favourited KCM); the direct KAStats grid reads model.display /
        // model.decoration instead, which the grouped model can't provide.
        readonly property var _kvis: (_fromGrouped && !_appKnown && gridView.sharedFavoritesModel)
                                     ? gridView._favoriteVisual(_sid) : null
        // Member icon names for a folder's 2x2 preview, resolved via the app model.
        readonly property var _folderIcons: {
            if (!_isFolder)
                return []
            const members = model.folderMembers || []
            const icons = []
            for (let i = 0; i < members.length && icons.length < 4; ++i) {
                icons.push(FavoriteVisual.resolve(gridView.appsModel, gridView.sharedFavoritesModel,
                                                  gridView.favoriteIdRole, members[i], gridView.defaultIcon).icon)
            }
            return icons
        }

        // Bounce this cell's app icon (Ctrl+D toggle feedback, #193). Folder rows
        // have no favourite to toggle, so they never get here.
        function bounceFeedback() { iconDelegate.bounceFeedback() }

        // A folder tile only for folder rows: most cells are apps (and the flat
        // All-apps grid has no folders), so don't build a hidden FolderCell in
        // every one of them.
        Loader {
            id: folderLoader
            anchors.fill: parent
            active: delegateRoot._isFolder
            sourceComponent: FolderCell {
                folderId: delegateRoot._isFolder ? (model.folderId || "") : ""
                folderName: delegateRoot._isFolder ? (model.display || "") : ""
                memberIcons: delegateRoot._folderIcons
                cellStyle: gridView.cellStyle
                hideLabel: gridView.hideLabelsOnFavorites && gridView.favoritesActive
                isCurrentItem: gridView.currentIndex === model.index && gridView.activeFocus
                dragSource: gridView.dragSource
                gridRow: model.index
                // Record the tile as current so focus returns here when the folder
                // closes (e.g. Esc), not to the search field.
                onClicked: {
                    gridView.currentIndex = model.index
                    gridView.openFolderRequested(model.folderId)
                }
                onContextRequested: gridView.folderContextMenuRequested(model.folderId)
            }
        }

        AppCell {
            id: iconDelegate
            anchors.fill: parent
            view: gridView
            cellIndex: model.index
            visible: !delegateRoot._isFolder
            appName: delegateRoot._fromShared
                ? ((delegateRoot._appKnown && delegateRoot._appData.name)
                   || model.display
                   || (delegateRoot._kvis && delegateRoot._kvis.display)
                   || "")
                : (model.name || "")
            appIcon: delegateRoot._fromShared
                ? ((delegateRoot._appKnown && delegateRoot._appData.iconName)
                   || model.decoration
                   || (delegateRoot._kvis && delegateRoot._kvis.decoration)
                   || gridView.defaultIcon)
                : (model.iconName || gridView.defaultIcon)
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
            hideLabel: gridView.hideLabelsOnFavorites && gridView.favoritesActive
            isCurrentItem: gridView.currentIndex === model.index && gridView.activeFocus
            newBadgeAllowed: !delegateRoot._fromShared
            storageId: delegateRoot._sid
            desktopFile: delegateRoot._fromShared
                ? (delegateRoot._appData ? delegateRoot._appData.desktopFile || "" : "")
                : (model.desktopFile || "")
            gridRow: model.index

            onClicked: function(mouse) {
                const desktopFile = delegateRoot._fromShared
                    ? (delegateRoot._appData ? delegateRoot._appData.desktopFile || "" : "")
                    : (model.desktopFile || "")
                if (mouse.button === Qt.RightButton) {
                    // Selection persists across right-click so the menu can
                    // surface "Add to selection" / "Remove from selection".
                    gridView.host.appMenuRequested(delegateRoot._sid, desktopFile, gridView.selection.sidList())
                    return
                }
                if (gridView.multiSelectActive) {
                    gridView.currentIndex = model.index
                    if (gridView.selection.applyClickModifiers(mouse, model.index)) return
                }
                gridView.selection.clear()
                if (delegateRoot._fromShared) {
                    gridView.launchFavorite(delegateRoot._sid)
                } else {
                    gridView.host.launchAppRequested(model.index)
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
        // Off for a read-only grouped grid (the menu tree): no reorder / fold.
        enabled: gridView.groupEditable && gridView.sharedFavoritesModel !== null
    }

    EdgeAutoScroller {
        id: edgeScroller
        flickable: gridView
        dropArea: reorderArea
    }
}
