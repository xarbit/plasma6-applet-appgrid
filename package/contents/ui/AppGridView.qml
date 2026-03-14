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

    // Number of columns to display.
    property int columns: 6

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

    clip: true
    cacheBuffer: Kirigami.Units.gridUnit * 4
    cellWidth: Math.floor(width / columns)
    cellHeight: iconSize
               + Kirigami.Units.gridUnit * 2
               + Kirigami.Units.smallSpacing * 2
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: true
    currentIndex: -1
    highlightFollowsCurrentItem: true

    // Search field to return focus to when typing text
    property Item searchField: null
    // The apps model for section queries
    property var appsModel: null
    // Config toggle for recent apps
    property bool showRecentApps: true
    // Whether we're showing "All" (recents visible)
    // Hidden when sorting by most-used since frequent apps are already at the top.
    readonly property bool showRecents: showRecentApps
                                        && appsModel && !appsModel.filterCategory
                                        && !appsModel.searchText
                                        && appsModel.recentApps.length > 0
                                        && appsModel.sortMode === 0

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
            var newIdx = recentIndex - columns
            if (newIdx >= 0) {
                recentIndex = newIdx
            } else {
                // At top row of recents, go back to search
                recentIndex = -1
                currentIndex = -1
                if (searchField) searchField.forceActiveFocus()
            }
        } else if (currentIndex >= 0 && currentIndex < columns && showRecents) {
            // At top row of grid, move into recents
            var lastRow = Math.floor((recentCount - 1) / columns)
            recentIndex = Math.min(currentIndex + lastRow * columns, recentCount - 1)
            currentIndex = -1
        } else {
            moveCurrentIndexUp()
        }
    }
    Keys.onDownPressed: {
        if (recentIndex >= 0) {
            var newIdx = recentIndex + columns
            if (newIdx < recentCount) {
                recentIndex = newIdx
            } else {
                // Move from recents into grid
                currentIndex = Math.min(recentIndex % columns, count - 1)
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
    Keys.onPressed: function(event) {
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

    header: Column {
        width: gridView.width
        height: gridView.showRecents ? implicitHeight : 0
        visible: gridView.showRecents
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            leftPadding: Kirigami.Units.largeSpacing
            text: i18n("Recently Used")
            font.bold: true
            opacity: 0.7
        }

        Flow {
            width: parent.width

            Repeater {
                model: gridView.showRecents ? gridView.appsModel.recentApps : []
                delegate: Item {
                    id: recentDelegate
                    required property string modelData
                    required property int index
                    readonly property var appData: gridView.appsModel ? gridView.appsModel.getByStorageId(modelData) : ({})
                    width: gridView.cellWidth
                    height: gridView.cellHeight
                    visible: appData.name !== undefined

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
                        visible: gridView.recentIndex === recentDelegate.index && gridView.activeFocus
                    }

                    AppIconDelegate {
                        id: recentIcon
                        anchors.fill: parent
                        appName: recentDelegate.appData.name || ""
                        appIcon: recentDelegate.appData.iconName || "application-x-executable"
                        isCurrentItem: gridView.recentIndex === recentDelegate.index
                        iconSize: gridView.iconSize
                        onClicked: gridView.recentLaunched(recentDelegate.modelData)
                    }

                    Connections {
                        target: gridView
                        function onShakeAllIcons() { recentIcon.shake() }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.15)
        }

        PlasmaComponents.Label {
            leftPadding: Kirigami.Units.largeSpacing
            text: i18n("All Apps")
            font.bold: true
            opacity: 0.7
        }

        Item { width: 1; height: Kirigami.Units.smallSpacing }
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
            appGenericName: model.genericName || ""
            isCurrentItem: gridView.currentIndex === model.index
            iconSize: gridView.iconSize
            isNew: gridView.appsModel ? gridView.appsModel.isNewApp(model.storageId || "") : false
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    gridView.contextMenuRequested(model.index, model.storageId || "", model.desktopFile || "")
                } else {
                    gridView.launched(model.index)
                }
            }
        }

        Connections {
            target: gridView
            function onShakeAllIcons() { iconDelegate.shake() }
        }
    }
}
