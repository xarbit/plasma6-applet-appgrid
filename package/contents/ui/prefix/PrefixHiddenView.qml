/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import dev.xarbit.appgrid.models

import "../js/constants.js" as Const

ColumnLayout {
    id: hiddenView

    // The controller's LaunchStateStore. The list follows it live, also when
    // another launcher hides or unhides an app.
    required property var launchState

    HiddenAppsModel {
        id: hiddenApps
        launchState: hiddenView.launchState
    }

    anchors.fill: parent
    anchors.margins: Kirigami.Units.largeSpacing * 2
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.largeSpacing * 2

        PlasmaComponents.Label {
            text: i18nd("dev.xarbit.appgrid", "Hidden Applications")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            Layout.fillWidth: true
        }

        PlasmaComponents.Button {
            visible: !hiddenApps.empty
            icon.name: "edit-undo"
            text: i18nd("dev.xarbit.appgrid", "Unhide All")
            onClicked: hiddenApps.unhideAll()
        }
    }

    // Empty state
    Item {
        visible: hiddenApps.empty
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                source: "view-visible"
                opacity: 0.3
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nd("dev.xarbit.appgrid", "No hidden applications")
                opacity: 0.5
            }

            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18nd("dev.xarbit.appgrid", "Right-click any app in the grid to hide it")
                font: Kirigami.Theme.smallFont
                opacity: 0.35
            }
        }
    }

    // Hidden apps list
    PlasmaComponents.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !hiddenApps.empty
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ListView {
            id: hiddenList
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: hiddenApps

            delegate: PlasmaComponents.ItemDelegate {
                id: hiddenDelegate
                width: hiddenList.width
                height: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
                required property string storageId
                required property string name
                required property string iconName
                required property string genericName

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        source: hiddenDelegate.iconName || Const.DEFAULT_ICON
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: hiddenDelegate.name
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: hiddenDelegate.genericName
                            font: Kirigami.Theme.smallFont
                            opacity: 0.5
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-visible"
                        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Unhide")
                        Accessible.name: PlasmaComponents.ToolTip.text
                        PlasmaComponents.ToolTip.visible: hovered
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: hiddenApps.unhide(hiddenDelegate.storageId)
                    }
                }
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: !hiddenApps.empty
        text: i18ndp("dev.xarbit.appgrid", "%1 hidden application", "%1 hidden applications", hiddenApps.count)
        font: Kirigami.Theme.smallFont
        opacity: 0.35
        horizontalAlignment: Text.AlignHCenter
    }
}
