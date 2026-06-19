/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Plasmoid-free body of the Hidden Apps settings page: an info line, a filter
    field, an "Unhide All" button and the scrollable list of hidden apps with a
    per-row unhide button. Hosts inject the live `appsModel` and size this
    ColumnLayout. The hidden list is read and written straight on the model
    (appsModel.hiddenApps) — both the panel config dialog (Plasmoid.appsModel)
    and the daemon settings window (the controller's model) carry the live model,
    and AppGridController persists every change to the shared LaunchStateStore.
    Value bindings depend on `revision` so a host can force a re-read.

    (The plasmoid wrapper kept "Unhide All" in the ScrollViewKCM page header;
    here it lives inline so the same body works for the daemon window too.)
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../js/constants.js" as Const

ColumnLayout {
    id: root

    // -- Injected context --------------------------------------------------
    property var appsModel
    property int revision: 0

    property string _filter: ""
    readonly property var _hidden: (root.revision, (root.appsModel && root.appsModel.hiddenApps) || [])

    spacing: Kirigami.Units.smallSpacing

    readonly property var _filteredApps: {
        var apps = root._hidden
        if (!root._filter)
            return apps
        var needle = root._filter.toLowerCase()
        return apps.filter(function(sid) {
            if (!sid) return false
            if (sid.toLowerCase().indexOf(needle) >= 0) return true
            var info = root.appsModel ? root.appsModel.getByStorageId(sid) : null
            return info && info.name && info.name.toLowerCase().indexOf(needle) >= 0
        })
    }

    function _unhide(storageId) {
        var list = root._hidden.slice()
        var i = list.indexOf(storageId)
        if (i >= 0) {
            list.splice(i, 1)
            root.appsModel.hiddenApps = list
        }
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
            Layout.fillWidth: true
            enabled: root._hidden.length > 0
            placeholderText: i18nd("dev.xarbit.appgrid", "Filter hidden apps…")
            onTextChanged: root._filter = text
        }
        QQC2.Button {
            text: i18nd("dev.xarbit.appgrid", "Unhide All")
            icon.name: "edit-undo"
            enabled: root._hidden.length > 0
            onClicked: root.appsModel.hiddenApps = []
        }
    }

    // -- Scrollable list (with empty / no-match states) --------------------
    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ListView {
            id: hiddenList
            model: root._filteredApps
            spacing: 0
            reuseItems: true

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: root._hidden.length === 0
                icon.name: "view-visible"
                text: i18nd("dev.xarbit.appgrid", "No hidden applications")
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: root._hidden.length > 0 && root._filteredApps.length === 0
                icon.name: "system-search-symbolic"
                text: i18nd("dev.xarbit.appgrid", "No matches")
            }

            delegate: QQC2.ItemDelegate {
                width: hiddenList.width
                required property string modelData
                property var appInfo: (root.appsModel ? root.appsModel.getByStorageId(modelData) : null) || ({})

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        source: appInfo.iconName || Const.DEFAULT_ICON
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        QQC2.Label {
                            Layout.fillWidth: true
                            text: appInfo.name || modelData
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            visible: !!appInfo.name
                            text: modelData
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
                        onClicked: root._unhide(modelData)
                    }
                }
            }
        }
    }
}
