/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Scrollable grid view that groups applications by category.
    Each category has a label header, a Flow of app icons, and a separator.
    Supports keyboard navigation across all categories via a flat index.
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../controllers"
import "../widgets"
import "../js/gridnav.js" as GridNav
import "../js/gridmetrics.js" as GridMetrics
import "../js/categoryflatten.js" as CategoryFlatten
import "../js/constants.js" as Const

Flickable {
    id: categoryGrid

    clip: true

    WheelScroller { target: categoryGrid }

    property var appsModel: null
    property var groupedApps: []
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
    signal shakeAllIcons()

    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    focus: true

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

    property int currentIndex: -1
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
        : currentIndex >= 0 ? recentCount + currentIndex
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
        contentY = 0
        clearSelection()
        currentIndex = -1
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

    // Bumped on knownAppsChanged so each cell's isNew binding re-evaluates
    // without a Connections object per delegate.
    property int _knownAppsRevision: 0
    Connections {
        target: categoryGrid.appsModel
        function onKnownAppsChanged() { categoryGrid._knownAppsRevision++ }
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
            currentIndex = -1
        } else {
            currentIndex = flatApps.length > 0 ? 0 : -1
            recentIndex = -1
        }
        contentY = 0
    }

    function ensureVisible() {
        // Resolve the current flat index to its section via the prefix sums,
        // then scroll the live section delegate into view.
        if (currentIndex < 0) return
        var i = CategoryFlatten.sectionForFlatIndex(currentIndex, sectionStartIndices)
        if (i < 0) return
        var section = sectionRepeater.itemAt(i)
        if (!section) return
        var localIdx = currentIndex - sectionStartIndices[i]
        var row = Math.floor(localIdx / itemsPerRow)
        var itemY = section.y + section.children[0].height + row * cellHeight
        if (itemY < contentY)
            contentY = itemY
        else if (itemY + cellHeight > contentY + height)
            contentY = itemY + cellHeight - height
    }

    // Direction movers — encode the cursor-transition rules between
    // the recents row and the flat category grid. Wrapped by the
    // shift-extender so Shift+Arrow at a recents/grid boundary extends
    // the selection through the destination cell.
    function _moveLeft() {
        if (recentIndex > 0) recentIndex--
        else if (recentIndex < 0 && currentIndex > 0) {
            currentIndex--
            ensureVisible()
        }
    }
    function _moveRight() {
        if (recentIndex >= 0 && recentIndex < recentCount - 1) recentIndex++
        else if (recentIndex < 0 && currentIndex < flatApps.length - 1) {
            currentIndex++
            ensureVisible()
        }
    }
    function _moveUp() {
        if (recentIndex >= 0) {
            recentIndex -= itemsPerRow
        } else if (currentIndex >= itemsPerRow) {
            currentIndex -= itemsPerRow
            ensureVisible()
        } else if (currentIndex >= 0 && showRecents && recentCount > 0) {
            recentIndex = GridNav.recentsLandingFromGrid(currentIndex, recentCount, itemsPerRow)
            currentIndex = -1
            contentY = 0
        }
    }
    function _moveDown() {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + itemsPerRow
            if (newIdx < recentCount) {
                recentIndex = newIdx
            } else {
                currentIndex = GridNav.gridLandingFromRecents(recentIndex, itemsPerRow, flatApps.length)
                recentIndex = -1
                ensureVisible()
            }
        } else if (currentIndex + itemsPerRow < flatApps.length) {
            currentIndex += itemsPerRow
            ensureVisible()
        }
    }
    function _exitToSearchField() {
        recentIndex = -1
        currentIndex = -1
        if (searchField) searchField.forceActiveFocus()
    }

    Keys.onLeftPressed: function(event) {
        // Alt+Left belongs to the category bar — let it bubble up.
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        _arrowMoveWithSelection(event, _moveLeft)
    }
    Keys.onRightPressed: function(event) {
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        _arrowMoveWithSelection(event, _moveRight)
    }
    Keys.onUpPressed: function(event) {
        // Leaving the grid is a focus transfer, not a cursor move, so it
        // bypasses the shift-extender. Top row of recents exits straight
        // to the search field; first row of the category grid exits when
        // recents is hidden.
        const exitingRecentsTop = recentIndex >= 0 && recentIndex < itemsPerRow
        const exitingGridTopWithoutRecents =
            recentIndex < 0 && currentIndex >= 0
            && currentIndex < itemsPerRow
            && (!showRecents || recentCount === 0)
        if (exitingRecentsTop || exitingGridTopWithoutRecents) {
            _exitToSearchField()
            return
        }
        _arrowMoveWithSelection(event, _moveUp)
    }
    Keys.onDownPressed: function(event) {
        if (recentIndex < 0 && currentIndex < 0) {
            // No focus yet — claim it (selectFirst handles recents-first preference).
            selectFirst()
            return
        }
        _arrowMoveWithSelection(event, _moveDown)
    }
    function _launchCurrent() {
        if (recentIndex >= 0 && recentIndex < recentCount && appsModel)
            recentLaunched(appsModel.recentApps[recentIndex])
        else if (currentIndex >= 0 && currentIndex < flatApps.length)
            launched(flatApps[currentIndex].proxyIndex)
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
            event.accepted = true
        }
    }

    function scrollToCategory(name) {
        for (var i = 0; i < sectionRepeater.count; i++) {
            var section = sectionRepeater.itemAt(i)
            if (section && groupedApps[i] && groupedApps[i].category === name) {
                contentY = section.y
                currentIndex = sectionStartIndices[i]
                recentIndex = -1
                return
            }
        }
    }

    // -- Content --

    Column {
        id: contentColumn
        width: parent.width

        // Recently used section at the top
        RecentAppsHeader {
            id: catRecentHeader
            width: contentColumn.width
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
                categoryGrid.currentIndex = -1
                categoryGrid.forceActiveFocus()
                return true
            }

            Connections {
                target: categoryGrid
                function onShakeAllIcons() { catRecentHeader.shakeAll() }
            }
        }

        Repeater {
            id: sectionRepeater
            model: categoryGrid.groupedApps

            delegate: Column {
                id: sectionColumn
                width: contentColumn.width
                spacing: Kirigami.Units.smallSpacing

                // Flat-index offset of this section, from the precomputed
                // prefix-sum array (O(1) instead of re-summing prior sections).
                readonly property int globalStartIndex: categoryGrid.sectionStartIndices[index] || 0

                SectionLabel {
                    leftPadding: Kirigami.Units.largeSpacing
                    topPadding: (index > 0 || categoryGrid.showRecents) ? Kirigami.Units.largeSpacing : 0
                    text: modelData.category
                }

                Flow {
                    width: parent.width

                    Repeater {
                        model: modelData.apps

                        delegate: Item {
                            width: categoryGrid.cellWidth
                            height: categoryGrid.cellHeight

                            readonly property int flatIndex: sectionColumn.globalStartIndex + index

                            GridHighlight {
                                cellWidth: categoryGrid.cellWidth
                                cellHeight: categoryGrid.cellHeight
                                visible: categoryGrid.activeFocus && categoryGrid.currentIndex === flatIndex
                            }

                            AppIconDelegate {
                                id: catIconDelegate
                                anchors.fill: parent
                                appName: modelData.name || ""
                                appIcon: modelData.iconName || Const.DEFAULT_ICON
                                iconGeneration: categoryGrid.appsModel ? categoryGrid.appsModel.iconGeneration : 0
                                appComment: modelData.comment || ""
                                installSource: modelData.installSource || ""
                                showTooltip: categoryGrid.showTooltips
                                iconSize: categoryGrid.iconSize
                                fontScale: categoryGrid.fontScale
                                hoverAnimation: categoryGrid.hoverAnimation
                                shadowEnabled: categoryGrid.shadowEnabled
                                hoverHighlight: categoryGrid.hoverHighlight
                                isCurrentItem: categoryGrid.currentIndex === parent.flatIndex && categoryGrid.activeFocus
                                isNew: {
                                    categoryGrid._knownAppsRevision // re-eval when knownApps changes
                                    return categoryGrid.showNewAppBadge && categoryGrid.appsModel
                                        ? categoryGrid.appsModel.isNewApp(modelData.storageId || "") : false
                                }
                                storageId: modelData.storageId || ""
                                desktopFile: modelData.desktopFile || ""
                                dragSource: categoryGrid.dragSource

                                selected: categoryGrid.multiSelectActive
                                          && !!categoryGrid.selectedSids[modelData.storageId || ""]
                                selectionAnchor: categoryGrid.multiSelectActive
                                                 && categoryGrid.selectionAnchor === parent.flatIndex
                                                 && categoryGrid.selectionCount > 0
                                multiSelectionSids: selected ? categoryGrid.selectedSidList() : []
                                multiSelectionUrls: selected ? categoryGrid.selectedDesktopFileUrls() : []
                                multiSelectionIcons: selected ? categoryGrid.selectedIconNames() : []

                                onClicked: function(mouse) {
                                    const sid = modelData.storageId || ""
                                    if (mouse.button === Qt.RightButton) {
                                        // Selection persists — menu shows
                                        // "Add to selection" / "Remove from
                                        // selection" based on popup item.
                                        categoryGrid.contextMenuRequested(modelData.proxyIndex, sid, modelData.desktopFile || "")
                                        return
                                    }
                                    if (categoryGrid.multiSelectActive) {
                                        categoryGrid.currentIndex = parent.flatIndex
                                        if (categoryGrid.applyClickModifiers(mouse, parent.flatIndex)) return
                                    }
                                    categoryGrid.clearSelection()
                                    categoryGrid.launched(modelData.proxyIndex)
                                }

                            }

                            Connections {
                                target: categoryGrid
                                function onShakeAllIcons() { catIconDelegate.shake() }
                            }
                        }
                    }
                }

                HorizontalDivider {
                    width: parent.width
                    visible: index < categoryGrid.groupedApps.length - 1
                    opacity: categoryGrid.showDividers ? 1 : 0
                }
            }
        }
    }
}
