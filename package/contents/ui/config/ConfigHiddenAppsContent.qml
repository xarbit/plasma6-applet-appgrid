/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the Hidden Apps settings page: an info line, a filter
    field, an "Unhide All" button and the scrollable list of hidden apps with a
    per-row unhide button. Hosts inject the controller's launch state store and
    size this ColumnLayout. The list follows the store live (also another
    launcher's hides) and unhides there, so every launcher sees it at once.

    (The plasmoid wrapper kept "Unhide All" in the ScrollViewKCM page header;
    here it lives inline so the same body works for the daemon window too.)
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import dev.xarbit.appgrid.models

import "../widgets"
import "../js/constants.js" as Const

ColumnLayout {
    id: root

    // -- Injected context --------------------------------------------------
    // The controller's LaunchStateStore.
    property var launchState

    spacing: Kirigami.Units.smallSpacing

    HiddenAppsModel {
        id: hiddenApps
        launchState: root.launchState
        filter: filterField.text
    }

    // -- Header: info, filter, Unhide All ----------------------------------
    QQC2.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        text: i18nd("dev.xarbit.appgrid", "Right-click any app in the grid to hide it, or type h: in the search bar.")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Kirigami.SearchField {
            id: filterField
            Layout.fillWidth: true
            enabled: !hiddenApps.empty
            placeholderText: i18nd("dev.xarbit.appgrid", "Filter hidden apps…")
        }
        QQC2.Button {
            text: i18nd("dev.xarbit.appgrid", "Unhide All")
            icon.name: "edit-undo"
            enabled: !hiddenApps.empty
            onClicked: hiddenApps.unhideAll()
        }
    }

    // -- Scrollable list (with empty / no-match states) --------------------
    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ListView {
            id: hiddenList
            model: hiddenApps
            spacing: 0
            reuseItems: true

            EmptyStateMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: hiddenApps.empty
                iconSource: "view-visible"
                text: i18nd("dev.xarbit.appgrid", "No hidden applications")
            }

            EmptyStateMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: !hiddenApps.empty && hiddenApps.count === 0
                iconSource: "system-search-symbolic"
                text: i18nd("dev.xarbit.appgrid", "No matches")
            }

            delegate: QQC2.ItemDelegate {
                id: hiddenDelegate
                width: hiddenList.width
                required property string storageId
                required property string name
                required property string iconName

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        source: hiddenDelegate.iconName || Const.DEFAULT_ICON
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: hiddenDelegate.name
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            // The id, when the name isn't just the id again.
                            visible: hiddenDelegate.name !== hiddenDelegate.storageId
                            text: hiddenDelegate.storageId
                            font: Kirigami.Theme.smallFont
                            opacity: 0.4
                            elide: Text.ElideRight
                        }
                    }
                    QQC2.ToolButton {
                        icon.name: "view-visible"
                        QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Unhide")
                        Accessible.name: QQC2.ToolTip.text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        onClicked: hiddenApps.unhide(hiddenDelegate.storageId)
                    }
                }
            }
        }
    }
}
