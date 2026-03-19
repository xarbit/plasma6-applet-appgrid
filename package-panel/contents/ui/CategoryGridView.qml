/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Scrollable grid view that groups applications by category.
    Each category has a label header, a Flow of app icons, and a separator.
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

    signal launched(int proxyIndex)
    signal recentLaunched(string storageId)
    signal contextMenuRequested(int proxyIndex, string storageId, string desktopFile)

    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    function scrollToCategory(name) {
        for (var i = 0; i < sectionRepeater.count; i++) {
            var section = sectionRepeater.itemAt(i)
            if (section && groupedApps[i] && groupedApps[i].category === name) {
                contentY = section.y
                return
            }
        }
    }

    Column {
        id: contentColumn
        width: parent.width

        // Recently used section at the top
        RecentAppsHeader {
            width: contentColumn.width
            height: categoryGrid.showRecents ? implicitHeight : 0
            visible: categoryGrid.showRecents
            appsModel: categoryGrid.appsModel
            cellWidth: categoryGrid.cellWidth
            cellHeight: categoryGrid.cellHeight
            iconSize: categoryGrid.iconSize
            currentRecentIndex: -1
            gridHasFocus: false
            favoritesActive: false
            hideBottomLabel: true
            showDividers: categoryGrid.showDividers
            onRecentLaunched: function(storageId) { categoryGrid.recentLaunched(storageId) }
            onContextMenuRequested: function(storageId, desktopFile) {
                categoryGrid.contextMenuRequested(-1, storageId, desktopFile)
            }
        }

        Repeater {
            id: sectionRepeater
            model: categoryGrid.groupedApps

            delegate: Column {
                width: contentColumn.width
                spacing: Kirigami.Units.smallSpacing

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

                        delegate: AppIconDelegate {
                            width: categoryGrid.cellWidth
                            height: categoryGrid.cellHeight
                            appName: modelData.name || ""
                            appIcon: modelData.iconName || "application-x-executable"
                            iconSize: categoryGrid.iconSize
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton)
                                    categoryGrid.contextMenuRequested(modelData.proxyIndex, modelData.storageId || "", modelData.desktopFile || "")
                                else
                                    categoryGrid.launched(modelData.proxyIndex)
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
