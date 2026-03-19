/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

ColumnLayout {
    id: hiddenView

    readonly property var hiddenApps: Plasmoid.appsModel ? Plasmoid.appsModel.hiddenApps : []

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
            visible: hiddenView.hiddenApps.length > 0
            icon.name: "edit-undo"
            text: i18nd("dev.xarbit.appgrid", "Unhide All")
            onClicked: {
                Plasmoid.appsModel.hiddenApps = []
                Plasmoid.configuration.hiddenApps = []
            }
        }
    }

    // Empty state
    Item {
        visible: hiddenView.hiddenApps.length === 0
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
        visible: hiddenView.hiddenApps.length > 0
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ListView {
            id: hiddenList
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: hiddenView.hiddenApps

            delegate: PlasmaComponents.ItemDelegate {
                id: hiddenDelegate
                width: hiddenList.width
                height: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2

                property var appInfo: Plasmoid.appsModel ? Plasmoid.appsModel.getByStorageId(modelData) : ({})

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        source: hiddenDelegate.appInfo.iconName || "application-x-executable"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: hiddenDelegate.appInfo.name || modelData
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: hiddenDelegate.appInfo.genericName || ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.5
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-visible"
                        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Unhide")
                        PlasmaComponents.ToolTip.visible: hovered
                        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: {
                            Plasmoid.appsModel.unhideApp(modelData)
                            Plasmoid.configuration.hiddenApps = Plasmoid.appsModel.hiddenApps
                        }
                    }
                }
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        visible: hiddenView.hiddenApps.length > 0
        text: i18nd("dev.xarbit.appgrid", "%1 hidden application(s)", hiddenView.hiddenApps.length)
        font: Kirigami.Theme.smallFont
        opacity: 0.35
        horizontalAlignment: Text.AlignHCenter
    }
}
