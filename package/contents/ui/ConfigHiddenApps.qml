/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property var cfg_hiddenApps: Plasmoid.configuration.hiddenApps

    ListModel { id: hiddenAppsModel }
    Component.onCompleted: syncHiddenModel()
    onCfg_hiddenAppsChanged: syncHiddenModel()

    function syncHiddenModel() {
        hiddenAppsModel.clear()
        var apps = cfg_hiddenApps
        if (apps && apps.length) {
            for (var i = 0; i < apps.length; i++)
                if (apps[i] !== "")
                    hiddenAppsModel.append({ storageId: apps[i] })
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18nd("dev.xarbit.appgrid", "Right-click any app in the grid to hide it, or type h: in the search bar.")
        }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            visible: hiddenAppsModel.count === 0
            icon.name: "view-visible"
            text: i18nd("dev.xarbit.appgrid", "No hidden applications")
        }

        Repeater {
            model: hiddenAppsModel

            delegate: QQC2.ItemDelegate {
                Layout.fillWidth: true
                required property string storageId
                required property int index

                property var appInfo: Plasmoid.appsModel.getByStorageId(storageId) || ({})

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        source: appInfo.iconName || "application-x-executable"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        QQC2.Label {
                            Layout.fillWidth: true
                            text: appInfo.name || storageId
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            visible: !!appInfo.name
                            text: storageId
                            font: Kirigami.Theme.smallFont
                            opacity: 0.4
                            elide: Text.ElideRight
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "view-visible"
                        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Unhide")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: {
                            var list = page.cfg_hiddenApps.slice()
                            list.splice(index, 1)
                            page.cfg_hiddenApps = list
                        }
                    }
                }
            }
        }

        QQC2.Button {
            visible: hiddenAppsModel.count > 0
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignHCenter
            icon.name: "edit-undo"
            text: i18nd("dev.xarbit.appgrid", "Unhide All")
            onClicked: page.cfg_hiddenApps = []
        }
    }
}
