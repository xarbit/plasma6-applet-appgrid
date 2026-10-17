/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Scrollable grid view that groups applications by category.
    Each category has a label header and rows of app icons, separated by a
    divider. The rows come from CategoryRowsModel, so the ListView creates
    (and reuses) only the rows on screen. Supports keyboard navigation across
    all categories via a flat index.
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../controllers"
import "../widgets"
import "../js/gridnav.js" as GridNav
import "../js/gridmetrics.js" as GridMetrics
import "../js/categoryflatten.js" as CategoryFlatten
import "../js/constants.js" as Const

ListView {
    id: categoryGrid

    clip: true

    WheelScroller { target: categoryGrid }

    property var appsModel: null
    property var groupedApps: []
    // CategoryRowsModel from the controller; null leaves the view empty
    // (e.g. tests without the C++ plugin).
    property var rowsModel: null
    property real cellWidth: 100
    property real cellHeight: 100
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Label font scale, following the size preset (Scale.textScale).
    property real fontScale: 1.0
    // Icon delegate config, injected from the boundary's ConfigCache.
    required property int hoverAnimation
    required property bool shadowEnabled
    property bool hoverHighlight: true
    property bool showRecents: false
    property bool showDividers: true
    property bool showTooltips: true
    property bool showNewAppBadge: true
    property Item searchField: null
    // Shared with AppGridView so drag-out targets work from this view too.
    property DragSource dragSource: null

    signal launched(int proxyIndex)
    signal recentLaunched(string storageId)

    // Fired when Enter is pressed with more than one item selected —
    // GridPanel routes through the same threshold + confirm dialog as
    // the context-menu "Launch" action.
    signal bulkLaunchRequested(var sids)
    signal contextMenuRequested(int proxyIndex, string storageId, string desktopFile)
    signal categoryNavRequested(int direction)
    signal shakeAllIcons()

    model: rowsModel
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    focus: true

    // The rows follow the sections and the column count.
    Binding {
        target: categoryGrid.rowsModel
        property: "groupedApps"
        value: categoryGrid.groupedApps
        when: categoryGrid.rowsModel !== null
    }
    Binding {
        target: categoryGrid.rowsModel
        property: "columns"
        value: categoryGrid.itemsPerRow
        when: categoryGrid.rowsModel !== null
    }

    // -- Keyboard navigation --

    // Flat list of all apps across categories for index-based navigation, and
    // the per-section start offsets (prefix sums) for O(1) flat-index lookup
    // from a section delegate. Both are recomputed once per groupedApps change
    // (_rebuildFlatApps) rather than re-flattened on every read / re-summed
    // O(S²) per section delegate.
    property var flatApps: []
    property var sectionStartIndices: []

    function _rebuildFlatApps() {
        var r = CategoryFlatten.flatten(groupedApps)
        flatApps = r.flatApps
        sectionStartIndices = r.sectionStartIndices
    }

    property int appIndex: -1
    property int recentIndex: -1
    readonly property int itemsPerRow: GridMetrics.columnsForWidth(width, cellWidth, 1)
    readonly property int recentCount: showRecents && appsModel ? appsModel.recentApps.length : 0

    // -- Multi-select --
    // Always active in this view (no favorites/non-favorites split): the
    // user can select any visible app and drag it out, or drag a multi-
    // selection onto the Favorites tab to batch-add. See AppGridView for
    // the analogous favorites-aware variant.
    // SelectionState operates in a unified index space that spans the
    // recents row (0 .. recentCount-1) and the flat category grid
    // (recentCount .. end) so Shift+Arrow extends a range across the
    // boundary just like it does within either section.
    SelectionState {
        id: selection
        sidAt: function(idx) { return categoryGrid._unifiedSidAt(idx) }
        gridCount: categoryGrid.recentCount + categoryGrid.flatApps.length
    }
    readonly property int virtualIndex:
        recentIndex >= 0 ? recentIndex
        : appIndex >= 0 ? recentCount + appIndex
        : -1

    function _unifiedSidAt(virtualIdx) {
        if (virtualIdx < 0) return ""
        if (virtualIdx < recentCount)
            return appsModel ? (appsModel.recentApps[virtualIdx] || "") : ""
        const gridIdx = virtualIdx - recentCount
        if (gridIdx >= flatApps.length) return ""
        return flatApps[gridIdx].storageId || ""
    }
    readonly property bool multiSelectActive: flatApps.length > 0

    property alias selectedSids: selection.selectionSids
    property alias selectionAnchor: selection.anchor
    readonly property alias selectionCount: selection.selectionCount

    function selectionContainsSid(sid) { return selection.contains(sid) }
    function selectedSidList() { return selection.sidList() }

    // Public accessors take a flat-grid index; selection runs in the
    // unified (recents + grid) space, so translate at the boundary.
    function toggleSelectionAt(gridIdx) {
        if (multiSelectActive) selection.toggleAt(recentCount + gridIdx)
    }
    function toggleSelectionBySid(sid) {
        if (multiSelectActive) selection.toggleSid(sid, -1)
    }
    function rangeSelectTo(gridIdx) {
        if (multiSelectActive) selection.rangeTo(recentCount + gridIdx)
    }
    function applyClickModifiers(mouse, gridIdx) {
        return multiSelectActive
            ? selection.applyModClick(mouse, recentCount + gridIdx) : false
    }
    // Recents already sit at virtual indices 0 .. recentCount-1, no offset.
    function applyRecentClickModifiers(mouse, recentIdx) {
        return multiSelectActive
            ? selection.applyModClick(mouse, recentIdx) : false
    }
    function selectAllVisible() {
        if (multiSelectActive) selection.selectAll(virtualIndex)
    }
    function clearSelection() { selection.clear() }
    // Reset to a clean, unselected, scrolled-to-top state. Used after
    // search/filter changes and before re-showing the panel.
    function resetView() {
        positionViewAtBeginning()
        clearSelection()
        appIndex = -1
        recentIndex = -1
    }
    function selectedDesktopFileUrls() { return selection.desktopFileUrls(appsModel) }
    function selectedIconNames() { return selection.iconNames(appsModel) }

    // Clear selection whenever the grouped model is rebuilt (search, category
    // pick) so the user doesn't carry ghost selections across filter changes.
    onGroupedAppsChanged: {
        _rebuildFlatApps()
        clearSelection()
    }
    Component.onCompleted: _rebuildFlatApps()

    // Bumped on newAppsChanged so each cell's isNew binding re-evaluates
    // without a Connections object per delegate.
    property int _newAppsRevision: 0
    Connections {
        target: categoryGrid.appsModel
        function onNewAppsChanged() { categoryGrid._newAppsRevision++ }
    }

    function _arrowMoveWithSelection(event, moveFn) {
        GridNav.arrowMoveWithSelection(selection, multiSelectActive,
                                        event, moveFn,
                                        function() { return virtualIndex })
    }

    Shortcut {
        sequence: StandardKey.SelectAll
        enabled: categoryGrid.multiSelectActive && categoryGrid.activeFocus
                 && categoryGrid.flatApps.length > 0
        onActivated: categoryGrid.selectAllVisible()
    }

    function selectFirst() {
        if (showRecents && recentCount > 0) {
            recentIndex = 0
            appIndex = -1
        } else {
            appIndex = flatApps.length > 0 ? 0 : -1
            recentIndex = -1
        }
        positionViewAtBeginning()
    }

    function ensureVisible() {
        if (appIndex < 0 || !rowsModel) return
        var row = rowsModel.rowForFlatIndex(appIndex)
        if (row >= 0)
            positionViewAtIndex(row, ListView.Contain)
    }

    // Direction movers — encode the cursor-transition rules between
    // the recents row and the flat category grid. Wrapped by the
    // shift-extender so Shift+Arrow at a recents/grid boundary extends
    // the selection through the destination cell.
    function _moveLeft() {
        if (recentIndex > 0) recentIndex--
        else if (recentIndex < 0 && appIndex > 0) {
            appIndex--
            ensureVisible()
        }
    }
    function _moveRight() {
        if (recentIndex >= 0 && recentIndex < recentCount - 1) recentIndex++
        else if (recentIndex < 0 && appIndex < flatApps.length - 1) {
            appIndex++
            ensureVisible()
        }
    }
    function _moveUp() {
        if (recentIndex >= 0) {
            recentIndex -= itemsPerRow
        } else if (appIndex >= itemsPerRow) {
            appIndex -= itemsPerRow
            ensureVisible()
        } else if (appIndex >= 0 && showRecents && recentCount > 0) {
            recentIndex = GridNav.recentsLandingFromGrid(appIndex, recentCount, itemsPerRow)
            appIndex = -1
            positionViewAtBeginning()
        }
    }
    function _moveDown() {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + itemsPerRow
            if (newIdx < recentCount) {
                recentIndex = newIdx
            } else {
                appIndex = GridNav.gridLandingFromRecents(recentIndex, itemsPerRow, flatApps.length)
                recentIndex = -1
                ensureVisible()
            }
        } else if (appIndex + itemsPerRow < flatApps.length) {
            appIndex += itemsPerRow
            ensureVisible()
        }
    }
    function _exitToSearchField() {
        recentIndex = -1
        appIndex = -1
        if (searchField) searchField.forceActiveFocus()
    }

    GridKeyboardNav {
        id: keyNav
        searchField: categoryGrid.searchField
        onCategoryNavRequested: direction => categoryGrid.categoryNavRequested(direction)
    }
    Keys.onLeftPressed: function(event) {
        if (keyNav.handleAltArrow(event, -1)) return
        _arrowMoveWithSelection(event, _moveLeft)
    }
    Keys.onRightPressed: function(event) {
        if (keyNav.handleAltArrow(event, 1)) return
        _arrowMoveWithSelection(event, _moveRight)
    }
    Keys.onUpPressed: function(event) {
        // Leaving the grid is a focus transfer, not a cursor move, so it
        // bypasses the shift-extender. Top row of recents exits straight
        // to the search field; first row of the category grid exits when
        // recents is hidden.
        const exitingRecentsTop = recentIndex >= 0 && recentIndex < itemsPerRow
        const exitingGridTopWithoutRecents =
            recentIndex < 0 && appIndex >= 0
            && appIndex < itemsPerRow
            && (!showRecents || recentCount === 0)
        if (exitingRecentsTop || exitingGridTopWithoutRecents) {
            _exitToSearchField()
            return
        }
        _arrowMoveWithSelection(event, _moveUp)
    }
    Keys.onDownPressed: function(event) {
        if (recentIndex < 0 && appIndex < 0) {
            // No focus yet — claim it (selectFirst handles recents-first preference).
            selectFirst()
            return
        }
        _arrowMoveWithSelection(event, _moveDown)
    }
    function _launchCurrent() {
        if (recentIndex >= 0 && recentIndex < recentCount && appsModel)
            recentLaunched(appsModel.recentApps[recentIndex])
        else if (appIndex >= 0 && appIndex < flatApps.length)
            launched(flatApps[appIndex].proxyIndex)
        clearSelection()
    }
    function activateCurrent() {
        const sids = selectedSidList()
        if (sids.length > 1) {
            bulkLaunchRequested(sids)
            clearSelection()
        } else {
            _launchCurrent()
        }
    }
    Keys.onReturnPressed: activateCurrent()
    Keys.onEnterPressed: activateCurrent()
    Keys.onEscapePressed: function(event) {
        if (selection.consumeEscape()) event.accepted = true
    }
    Keys.onTabPressed: function(event) { event.accepted = true }
    Keys.onBacktabPressed: function(event) { event.accepted = true }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return
        // Space toggles selection on focused item (see AppGridView). Caught
        // here ahead of the search-bar typing redirect that would otherwise
        // swallow the printable " ".
        if (event.key === Qt.Key_Space && multiSelectActive
                && appIndex >= 0 && recentIndex < 0) {
            toggleSelectionAt(appIndex)
            event.accepted = true
            return
        }
        if (keyNav.forwardTyping(event)) {
            appIndex = -1
            recentIndex = -1
        }
    }

    function scrollToCategory(name) {
        if (!rowsModel) return
        var row = rowsModel.rowForCategory(name)
        if (row < 0) return
        positionViewAtIndex(row, ListView.Beginning)
        for (var i = 0; i < groupedApps.length; i++) {
            if (groupedApps[i].category === name) {
                appIndex = sectionStartIndices[i]
                recentIndex = -1
                return
            }
        }
    }


    // -- Content --

    // Recently used section at the top
    header: RecentAppsHeader {
        id: catRecentHeader
        width: categoryGrid.width
        height: categoryGrid.showRecents ? implicitHeight : 0
        visible: categoryGrid.showRecents
        appsModel: categoryGrid.appsModel
        cellWidth: categoryGrid.cellWidth
        cellHeight: categoryGrid.cellHeight
        iconSize: categoryGrid.iconSize
        hoverAnimation: categoryGrid.hoverAnimation
        shadowEnabled: categoryGrid.shadowEnabled
        hoverHighlight: categoryGrid.hoverHighlight
        currentRecentIndex: categoryGrid.recentIndex
        gridHasFocus: categoryGrid.activeFocus
        favoritesActive: false
        hideBottomLabel: true
        showDividers: categoryGrid.showDividers
        showTooltips: categoryGrid.showTooltips
        dragSource: categoryGrid.dragSource
        multiSelectActive: categoryGrid.multiSelectActive
        selectionSids: categoryGrid.selectedSids
        multiSelectionUrls: categoryGrid.selectedDesktopFileUrls()
        multiSelectionIcons: categoryGrid.selectedIconNames()
        onRecentLaunched: function(storageId) { categoryGrid.recentLaunched(storageId) }
        onContextMenuRequested: function(storageId, desktopFile) {
            categoryGrid.contextMenuRequested(-1, storageId, desktopFile)
        }
        tryModifierClick: function(recentIdx, mouse) {
            if (!categoryGrid.applyRecentClickModifiers(mouse, recentIdx)) return false
            categoryGrid.recentIndex = recentIdx
            categoryGrid.appIndex = -1
            categoryGrid.forceActiveFocus()
            return true
        }

        Connections {
            target: categoryGrid
            function onShakeAllIcons() { catRecentHeader.shakeAll() }
        }
    }

    // One row: a category header (with the divider closing the previous
    // category) or up to itemsPerRow app cells.
    delegate: Item {
        id: rowItem

        required property string kind
        required property string category
        required property int section
        required property int firstIndex
        required property var apps

        readonly property bool isHeader: kind === "header"

        width: ListView.view.width
        height: isHeader ? headerColumn.implicitHeight : categoryGrid.cellHeight

        Column {
            id: headerColumn
            width: parent.width
            visible: rowItem.isHeader

            Item {
                width: 1
                height: Kirigami.Units.smallSpacing
                visible: rowItem.section > 0
            }
            HorizontalDivider {
                width: parent.width
                visible: rowItem.section > 0
                opacity: categoryGrid.showDividers ? 1 : 0
            }
            SectionLabel {
                leftPadding: Kirigami.Units.largeSpacing
                topPadding: (rowItem.section > 0 || categoryGrid.showRecents) ? Kirigami.Units.largeSpacing : 0
                bottomPadding: Kirigami.Units.smallSpacing
                text: rowItem.category
            }
        }

        Row {
            visible: !rowItem.isHeader

            Repeater {
                model: rowItem.isHeader ? 0 : categoryGrid.itemsPerRow

                delegate: Item {
                    id: cell

                    required property int index
                    // The app in this cell; a short last row leaves the rest empty.
                    readonly property var app: rowItem.apps[index]
                    readonly property var appData: app || ({})
                    readonly property int flatIndex: rowItem.firstIndex + index

                    width: categoryGrid.cellWidth
                    height: categoryGrid.cellHeight
                    visible: app !== undefined

                    GridHighlight {
                        cellWidth: categoryGrid.cellWidth
                        cellHeight: categoryGrid.cellHeight
                        visible: categoryGrid.activeFocus && categoryGrid.appIndex === cell.flatIndex
                    }

                    AppIconDelegate {
                        id: catIconDelegate
                        anchors.fill: parent
                        appName: cell.appData.name || ""
                        appIcon: cell.appData.iconName || Const.DEFAULT_ICON
                        iconGeneration: categoryGrid.appsModel ? categoryGrid.appsModel.iconGeneration : 0
                        appComment: cell.appData.comment || ""
                        installSource: cell.appData.installSource || ""
                        showTooltip: categoryGrid.showTooltips
                        iconSize: categoryGrid.iconSize
                        fontScale: categoryGrid.fontScale
                        hoverAnimation: categoryGrid.hoverAnimation
                        shadowEnabled: categoryGrid.shadowEnabled
                        hoverHighlight: categoryGrid.hoverHighlight
                        isCurrentItem: categoryGrid.appIndex === cell.flatIndex && categoryGrid.activeFocus
                        isNew: {
                            categoryGrid._newAppsRevision // re-eval when used apps change
                            return categoryGrid.showNewAppBadge && categoryGrid.appsModel
                                ? categoryGrid.appsModel.isNewApp(cell.appData.storageId || "") : false
                        }
                        storageId: cell.appData.storageId || ""
                        desktopFile: cell.appData.desktopFile || ""
                        dragSource: categoryGrid.dragSource

                        selected: categoryGrid.multiSelectActive
                                  && !!categoryGrid.selectedSids[cell.appData.storageId || ""]
                        selectionAnchor: categoryGrid.multiSelectActive
                                         && categoryGrid.selectionAnchor === cell.flatIndex
                                         && categoryGrid.selectionCount > 0
                        multiSelectionSids: selected ? categoryGrid.selectedSidList() : []
                        multiSelectionUrls: selected ? categoryGrid.selectedDesktopFileUrls() : []
                        multiSelectionIcons: selected ? categoryGrid.selectedIconNames() : []

                        onClicked: function(mouse) {
                            const sid = cell.appData.storageId || ""
                            if (mouse.button === Qt.RightButton) {
                                // Selection persists — menu shows
                                // "Add to selection" / "Remove from
                                // selection" based on popup item.
                                categoryGrid.contextMenuRequested(cell.appData.proxyIndex, sid, cell.appData.desktopFile || "")
                                return
                            }
                            if (categoryGrid.multiSelectActive) {
                                categoryGrid.appIndex = cell.flatIndex
                                if (categoryGrid.applyClickModifiers(mouse, cell.flatIndex)) return
                            }
                            categoryGrid.clearSelection()
                            categoryGrid.launched(cell.appData.proxyIndex)
                        }
                    }

                    Connections {
                        target: categoryGrid
                        function onShakeAllIcons() { catIconDelegate.shake() }
                    }
                }
            }
        }
    }
}
