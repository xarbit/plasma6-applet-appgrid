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

    Keys.onLeftPressed: {
        if (recentIndex > 0) { recentIndex-- }
        else if (currentIndex > 0) { currentIndex--; ensureVisible() }
    }
    Keys.onRightPressed: {
        if (recentIndex >= 0 && recentIndex < recentCount - 1) { recentIndex++ }
        else if (currentIndex < flatApps.length - 1) { currentIndex++; ensureVisible() }
    }
    Keys.onUpPressed: {
        if (recentIndex >= 0) {
            var newIdx = recentIndex - itemsPerRow
            if (newIdx >= 0) { recentIndex = newIdx }
            else { recentIndex = -1; currentIndex = -1; if (searchField) searchField.forceActiveFocus() }
        } else if (currentIndex >= itemsPerRow) {
            currentIndex -= itemsPerRow; ensureVisible()
        } else if (currentIndex >= 0 && showRecents && recentCount > 0) {
            // Move from first row of categories into recents
            var lastRow = Math.floor((recentCount - 1) / itemsPerRow)
            recentIndex = Math.min(currentIndex + lastRow * itemsPerRow, recentCount - 1)
            currentIndex = -1
            contentY = 0
        } else if (currentIndex >= 0) {
            currentIndex = -1
            if (searchField) searchField.forceActiveFocus()
        }
    }
    Keys.onDownPressed: {
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
            currentIndex += itemsPerRow; ensureVisible()
        }
    }
    Keys.onReturnPressed: {
        if (recentIndex >= 0 && recentIndex < recentCount && appsModel)
            recentLaunched(appsModel.recentApps[recentIndex])
        else if (currentIndex >= 0 && currentIndex < flatApps.length)
            launched(flatApps[currentIndex].proxyIndex)
    }
    Keys.onEnterPressed: Keys.onReturnPressed(event)
    Keys.onTabPressed: function(event) { event.accepted = true }
    Keys.onBacktabPressed: function(event) { event.accepted = true }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return
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

                            // Highlight for keyboard navigation
                            Rectangle {
                                anchors.centerIn: parent
                                width: categoryGrid.cellWidth - Kirigami.Units.smallSpacing * 2
                                height: categoryGrid.cellHeight - Kirigami.Units.smallSpacing * 2
                                radius: Kirigami.Units.cornerRadius
                                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                               Kirigami.Theme.highlightColor.g,
                                               Kirigami.Theme.highlightColor.b, 0.2)
                                border.width: 1
                                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                      Kirigami.Theme.highlightColor.g,
                                                      Kirigami.Theme.highlightColor.b, 0.6)
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
                                isCurrentItem: categoryGrid.currentIndex === parent.flatIndex
                                isNew: categoryGrid.showNewAppBadge && categoryGrid.appsModel
                                    ? categoryGrid.appsModel.isNewApp(modelData.storageId || "") : false
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton)
                                        categoryGrid.contextMenuRequested(modelData.proxyIndex, modelData.storageId || "", modelData.desktopFile || "")
                                    else
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
