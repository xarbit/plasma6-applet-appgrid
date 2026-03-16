/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Recently used apps header for the app grid view.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Column {
    id: recentHeader

    property var appsModel: null
    property real cellWidth: 100
    property real cellHeight: 100
    property real iconSize: Kirigami.Units.iconSizes.huge
    property int currentRecentIndex: -1
    property bool gridHasFocus: false

    signal recentLaunched(string storageId)
    signal shakeAll()

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents.Label {
        leftPadding: Kirigami.Units.largeSpacing
        text: i18nd("dev.xarbit.appgrid", "Recently Used")
        font.bold: true
        opacity: 0.7
    }

    Flow {
        width: parent.width

        Repeater {
            model: recentHeader.appsModel ? recentHeader.appsModel.recentApps : []
            delegate: Item {
                id: recentDelegate
                required property string modelData
                required property int index
                readonly property var appData: recentHeader.appsModel ? recentHeader.appsModel.getByStorageId(modelData) : ({})
                width: recentHeader.cellWidth
                height: recentHeader.cellHeight
                visible: appData.name !== undefined

                Rectangle {
                    anchors.centerIn: parent
                    width: recentHeader.cellWidth - Kirigami.Units.smallSpacing * 2
                    height: recentHeader.cellHeight - Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                   Kirigami.Theme.highlightColor.g,
                                   Kirigami.Theme.highlightColor.b, 0.2)
                    border.width: 1
                    border.color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                          Kirigami.Theme.highlightColor.g,
                                          Kirigami.Theme.highlightColor.b, 0.6)
                    visible: recentHeader.currentRecentIndex === recentDelegate.index && recentHeader.gridHasFocus
                }

                AppIconDelegate {
                    id: recentIcon
                    anchors.fill: parent
                    appName: recentDelegate.appData.name || ""
                    appIcon: recentDelegate.appData.iconName || "application-x-executable"
                    isCurrentItem: recentHeader.currentRecentIndex === recentDelegate.index
                    iconSize: recentHeader.iconSize
                    onClicked: recentHeader.recentLaunched(recentDelegate.modelData)
                }

                Connections {
                    target: recentHeader
                    function onShakeAll() { recentIcon.shake() }
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
        text: i18nd("dev.xarbit.appgrid", "All Apps")
        font.bold: true
        opacity: 0.7
    }

    Item { width: 1; height: Kirigami.Units.smallSpacing }
}
