/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Header-action layout editor. One row per action: a Bar/Menu/Off placement
    selector and up/down reorder. Drops into a Kirigami.FormLayout parent.
    Emits `edited` with the new "id:placement" StringList on any change.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

import "../js/headeractions.js" as HeaderActions

ColumnLayout {
    id: root

    property var actions: []
    // updateCheck only exists in universal builds; hide it from the editor
    // on distro builds where the in-app updater isn't compiled in.
    property bool universalBuild: true
    signal edited(var newList)

    spacing: Kirigami.Units.smallSpacing

    readonly property var labels: ({
        "updateCheck": i18nd("dev.xarbit.appgrid", "Update"),
        "sleep": i18nd("dev.xarbit.appgrid", "Sleep"),
        "hibernate": i18nd("dev.xarbit.appgrid", "Hibernate"),
        "restart": i18nd("dev.xarbit.appgrid", "Restart"),
        "shutdown": i18nd("dev.xarbit.appgrid", "Shut Down"),
        "lock": i18nd("dev.xarbit.appgrid", "Lock"),
        "logout": i18nd("dev.xarbit.appgrid", "Log Out"),
        "switchuser": i18nd("dev.xarbit.appgrid", "Switch User")
    })
    readonly property var placementOrder: ["bar", "menu", "off"]
    readonly property var placementLabel: ({
        "bar": i18nd("dev.xarbit.appgrid", "Bar"),
        "menu": i18nd("dev.xarbit.appgrid", "Menu"),
        "off": i18nd("dev.xarbit.appgrid", "Off")
    })

    ListModel { id: actionModel }

    function _entries() {
        var arr = []
        for (var i = 0; i < actionModel.count; ++i)
            arr.push({ id: actionModel.get(i).actionId, placement: actionModel.get(i).placement })
        return arr
    }
    function _matches(target) { return HeaderActions.entriesEqual(_entries(), target) }
    function _sync() {
        var target = HeaderActions.entries(root.actions, root.universalBuild)
        // Skip the rebuild when already in sync — our own edits round-trip
        // back through cfg_, and clearing mid-edit loses the row state.
        if (_matches(target))
            return
        actionModel.clear()
        for (var i = 0; i < target.length; ++i)
            actionModel.append({ actionId: target[i].id, placement: target[i].placement })
    }
    function _emit() { root.edited(HeaderActions.serialize(_entries())) }
    function _setPlacement(i, p) { actionModel.setProperty(i, "placement", p); _emit() }
    function _move(from, to) { actionModel.move(from, to, 1); _emit() }

    onActionsChanged: _sync()
    onUniversalBuildChanged: _sync()
    Component.onCompleted: _sync()

    Repeater {
        model: actionModel
        delegate: RowLayout {
            id: actionRow
            Layout.fillWidth: true
            required property int index
            required property string actionId
            required property string placement
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                source: HeaderActions.iconFor(actionRow.actionId)
                // Greyed when this action is hidden, so the row reads as
                // "off" at a glance.
                opacity: actionRow.placement === "off" ? 0.4 : 1.0
            }

            QQC2.Label {
                Layout.fillWidth: true
                // Floor width so the placement + reorder buttons can't squeeze
                // the action name down to a couple of elided characters (#191).
                Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                elide: Text.ElideRight
                text: root.labels[actionRow.actionId] || actionRow.actionId
                opacity: actionRow.placement === "off" ? 0.6 : 1.0
            }

            // Segmented Bar / Menu / Off placement selector.
            RowLayout {
                spacing: 0
                Repeater {
                    model: root.placementOrder
                    delegate: QQC2.Button {
                        required property string modelData
                        text: root.placementLabel[modelData]
                        flat: actionRow.placement !== modelData
                        highlighted: actionRow.placement === modelData
                        onClicked: root._setPlacement(actionRow.index, modelData)
                    }
                }
            }

            QQC2.ToolButton {
                icon.name: "arrow-up"
                display: QQC2.AbstractButton.IconOnly
                enabled: actionRow.index > 0
                onClicked: root._move(actionRow.index, actionRow.index - 1)
                QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Move up")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.ToolButton {
                icon.name: "arrow-down"
                display: QQC2.AbstractButton.IconOnly
                enabled: actionRow.index < actionModel.count - 1
                onClicked: root._move(actionRow.index, actionRow.index + 1)
                QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Move down")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
    }
}
