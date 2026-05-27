/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Scrollable grid view that groups applications by category.
    Each category has a label header, a Flow of app icons, and a separator.
    Supports keyboard navigation across all categories via a flat index.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Flickable {
    id: categoryGrid

    clip: true

    WheelScroller { target: categoryGrid }

    property var appsModel: null
    property var groupedApps: []
    property real cellWidth: 100
    property real cellHeight: 100
    property real iconSize: Kirigami.Units.iconSizes.huge
    property bool showRecents: false
    property bool showDividers: true
    property bool showTooltips: true
    property bool showNewAppBadge: true
    property Item searchField: null
    // Shared with AppGridView so drag-out targets work from this view too.
    property DragSource dragSource: null

    signal launched(int proxyIndex)
    signal recentLaunched(string storageId)
    signal contextMenuRequested(int proxyIndex, string storageId, string desktopFile)
    signal shakeAllIcons()

    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    focus: true

    // -- Keyboard navigation --

    // Flat list of all apps across categories for index-based navigation
    readonly property var flatApps: {
        var list = []
        for (var i = 0; i < groupedApps.length; i++) {
            var apps = groupedApps[i].apps
            for (var j = 0; j < apps.length; j++)
                list.push(apps[j])
        }
        return list
    }

    property int currentIndex: -1
    property int recentIndex: -1
    readonly property int itemsPerRow: Math.max(1, Math.floor(width / cellWidth))
    readonly property int recentCount: showRecents && appsModel ? appsModel.recentApps.length : 0

    // -- Multi-select --
    // Always active in this view (no favorites/non-favorites split): the
    // user can select any visible app and drag it out, or drag a multi-
    // selection onto the Favorites tab to batch-add. See AppGridView for
    // the analogous favorites-aware variant.
    SelectionState {
        id: selection
        sidAt: function(idx) {
            if (idx < 0 || idx >= categoryGrid.flatApps.length) return ""
            return categoryGrid.flatApps[idx].storageId || ""
        }
        gridCount: categoryGrid.flatApps.length
    }
    readonly property bool multiSelectActive: flatApps.length > 0

    property alias selectedSids: selection.selectionSids
    property alias selectionAnchor: selection.anchor
    readonly property alias selectionCount: selection.selectionCount

    function selectionContainsSid(sid) { return selection.contains(sid) }
    function selectedSidList() { return selection.sidList() }

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

    // Clear selection whenever the grouped model is rebuilt (search, category
    // pick) so the user doesn't carry ghost selections across filter changes.
    onGroupedAppsChanged: clearSelection()

    function _arrowMoveWithSelection(event, moveFn) {
        if (multiSelectActive)
            selection.extendOrMove(event, moveFn, function() { return currentIndex })
        else
            moveFn()
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
        // Find the delegate for the current index and scroll to it
        if (currentIndex < 0) return
        var globalIdx = 0
        for (var i = 0; i < sectionRepeater.count; i++) {
            var section = sectionRepeater.itemAt(i)
            if (!section) continue
            var apps = groupedApps[i].apps
            if (globalIdx + apps.length > currentIndex) {
                // The selected app is in this section
                var localIdx = currentIndex - globalIdx
                var row = Math.floor(localIdx / itemsPerRow)
                var itemY = section.y + section.children[0].height + row * cellHeight
                if (itemY < contentY)
                    contentY = itemY
                else if (itemY + cellHeight > contentY + height)
                    contentY = itemY + cellHeight - height
                return
            }
            globalIdx += apps.length
        }
    }

    Keys.onLeftPressed: function(event) {
        // Alt+Left belongs to the category bar — let it bubble up.
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        if (recentIndex > 0) { recentIndex-- }
        else _arrowMoveWithSelection(event, function() {
            if (currentIndex > 0) { currentIndex--; ensureVisible() }
        })
    }
    Keys.onRightPressed: function(event) {
        if (event.modifiers & Qt.AltModifier) { event.accepted = false; return }
        if (recentIndex >= 0 && recentIndex < recentCount - 1) { recentIndex++ }
        else _arrowMoveWithSelection(event, function() {
            if (currentIndex < flatApps.length - 1) { currentIndex++; ensureVisible() }
        })
    }
    Keys.onUpPressed: function(event) {
        if (recentIndex >= 0) {
            var newIdx = recentIndex - itemsPerRow
            if (newIdx >= 0) { recentIndex = newIdx }
            else { recentIndex = -1; currentIndex = -1; if (searchField) searchField.forceActiveFocus() }
        } else if (currentIndex >= itemsPerRow) {
            _arrowMoveWithSelection(event, function() {
                currentIndex -= itemsPerRow; ensureVisible()
            })
        } else if (currentIndex >= 0 && showRecents && recentCount > 0) {
            // Move from first row of categories into recents
            var lastRow = Math.floor((recentCount - 1) / itemsPerRow)
            recentIndex = Math.min(currentIndex + lastRow * itemsPerRow, recentCount - 1)
            currentIndex = -1
            contentY = 0
            clearSelection()
        } else if (currentIndex >= 0) {
            currentIndex = -1
            clearSelection()
            if (searchField) searchField.forceActiveFocus()
        }
    }
    Keys.onDownPressed: function(event) {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + itemsPerRow
            if (newIdx < recentCount) { recentIndex = newIdx }
            else {
                // Move from recents into first category row
                currentIndex = Math.min(recentIndex % itemsPerRow, flatApps.length - 1)
                recentIndex = -1
                ensureVisible()
            }
        } else if (currentIndex < 0) {
            selectFirst()
        } else if (currentIndex + itemsPerRow < flatApps.length) {
            _arrowMoveWithSelection(event, function() {
                currentIndex += itemsPerRow; ensureVisible()
            })
        }
    }
    function _launchCurrent() {
        if (recentIndex >= 0 && recentIndex < recentCount && appsModel)
            recentLaunched(appsModel.recentApps[recentIndex])
        else if (currentIndex >= 0 && currentIndex < flatApps.length)
            launched(flatApps[currentIndex].proxyIndex)
        clearSelection()
    }
    Keys.onReturnPressed: _launchCurrent()
    Keys.onEnterPressed: _launchCurrent()
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
        var globalIdx = 0
        for (var i = 0; i < sectionRepeater.count; i++) {
            var section = sectionRepeater.itemAt(i)
            if (section && groupedApps[i] && groupedApps[i].category === name) {
                contentY = section.y
                currentIndex = globalIdx
                recentIndex = -1
                return
            }
            globalIdx += groupedApps[i].apps.length
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
            currentRecentIndex: categoryGrid.recentIndex
            gridHasFocus: categoryGrid.activeFocus
            favoritesActive: false
            hideBottomLabel: true
            showDividers: categoryGrid.showDividers
            showTooltips: categoryGrid.showTooltips
            onRecentLaunched: function(storageId) { categoryGrid.recentLaunched(storageId) }
            onContextMenuRequested: function(storageId, desktopFile) {
                categoryGrid.contextMenuRequested(-1, storageId, desktopFile)
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

                // Track the global start index for this section
                readonly property int globalStartIndex: {
                    var idx = 0
                    for (var i = 0; i < index; i++)
                        idx += categoryGrid.groupedApps[i].apps.length
                    return idx
                }

                PlasmaComponents.Label {
                    leftPadding: Kirigami.Units.largeSpacing
                    topPadding: (index > 0 || categoryGrid.showRecents) ? Kirigami.Units.largeSpacing : 0
                    text: modelData.category
                    font.bold: true
                    opacity: 0.7
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
                                appIcon: modelData.iconName || "application-x-executable"
                                appComment: modelData.comment || ""
                                installSource: modelData.installSource || ""
                                showTooltip: categoryGrid.showTooltips
                                iconSize: categoryGrid.iconSize
                                isCurrentItem: categoryGrid.currentIndex === parent.flatIndex && categoryGrid.activeFocus
                                isNew: categoryGrid.showNewAppBadge && categoryGrid.appsModel
                                    ? categoryGrid.appsModel.isNewApp(modelData.storageId || "") : false
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
                                        if (selection.applyModClick(mouse, parent.flatIndex)) return
                                    }
                                    categoryGrid.clearSelection()
                                    categoryGrid.launched(modelData.proxyIndex)
                                }

                                Connections {
                                    target: categoryGrid.appsModel
                                    function onKnownAppsChanged() {
                                        catIconDelegate.isNew = categoryGrid.showNewAppBadge
                                            && categoryGrid.appsModel
                                            ? categoryGrid.appsModel.isNewApp(modelData.storageId || "") : false
                                    }
                                }
                            }

                            Connections {
                                target: categoryGrid
                                function onShakeAllIcons() { catIconDelegate.shake() }
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    width: parent.width
                    visible: index < categoryGrid.groupedApps.length - 1
                    opacity: categoryGrid.showDividers ? 1 : 0
                }
            }
        }
    }
}
