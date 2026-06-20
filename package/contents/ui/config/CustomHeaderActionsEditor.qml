/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Editor for user-defined custom header actions (#196). One row per action:
    icon picker, label, command, "run in terminal" toggle, Bar/Menu/Off placement,
    and delete. A "+" button appends a blank terminal action. Emits `edited` with
    the new StringList (one JSON object per entry) on any change.

    The model is (re)seeded from `entries` only on load / `reloadToken` change so
    typing into a field doesn't round-trip back through config and clear the row
    mid-edit. Empty-command rows are kept in the model for editing but dropped on
    serialize, so a half-typed action never persists or shows in the header.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.iconthemes as KIconThemes
import org.kde.kirigami as Kirigami

import "../js/customheaderactions.js" as CustomHeaderActions

ColumnLayout {
    id: root

    // Raw config StringList (one JSON object per entry).
    property var entries: []
    // Bump to force a reload from `entries` (after revert / load-defaults).
    property int reloadToken: 0
    signal edited(var newList)

    spacing: Kirigami.Units.smallSpacing

    ListModel { id: actionModel }

    function _ids() {
        var ids = []
        for (var i = 0; i < actionModel.count; ++i)
            ids.push(actionModel.get(i).actionId)
        return ids
    }
    function _rebuild() {
        actionModel.clear()
        var parsed = CustomHeaderActions.parse(root.entries)
        for (var i = 0; i < parsed.length; ++i) {
            actionModel.append({
                actionId: parsed[i].id,
                label: parsed[i].label,
                icon: parsed[i].icon,
                command: parsed[i].command,
                runInTerminal: parsed[i].runInTerminal,
                placement: parsed[i].placement
            })
        }
    }
    function _emit() {
        var arr = []
        for (var i = 0; i < actionModel.count; ++i) {
            var e = actionModel.get(i)
            arr.push({
                id: e.actionId,
                label: e.label,
                icon: e.icon,
                command: e.command,
                runInTerminal: e.runInTerminal,
                placement: e.placement
            })
        }
        root.edited(CustomHeaderActions.serialize(arr))
    }
    function _set(i, key, value) { actionModel.setProperty(i, key, value); _emit() }
    function _add() {
        var blank = CustomHeaderActions.blank(_ids())
        actionModel.append({
            actionId: blank.id, label: blank.label, icon: blank.icon,
            command: blank.command, runInTerminal: blank.runInTerminal,
            placement: blank.placement
        })
        // Not emitted yet: a blank (empty-command) row serializes to nothing, so
        // there is nothing to persist until the user types a command.
    }
    function _remove(i) { actionModel.remove(i); _emit() }

    onReloadTokenChanged: _rebuild()
    Component.onCompleted: _rebuild()

    Repeater {
        model: actionModel
        delegate: ColumnLayout {
            id: actionRow
            Layout.fillWidth: true
            required property int index
            required property string actionId
            required property string label
            required property string icon
            required property string command
            required property bool runInTerminal
            required property string placement
            spacing: Kirigami.Units.smallSpacing

            // Row 1: icon picker + label + delete.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                // Click the icon to pick one from the system icon browser.
                QQC2.Button {
                    flat: true
                    implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
                    implicitHeight: implicitWidth
                    onClicked: iconDialog.open()
                    QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Choose icon (%1)", actionRow.icon || CustomHeaderActions.DEFAULT_ICON)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.medium
                        height: width
                        source: actionRow.icon || CustomHeaderActions.DEFAULT_ICON
                    }

                    KIconThemes.IconDialog {
                        id: iconDialog
                        onIconNameChanged: iconName => root._set(actionRow.index, "icon", iconName)
                    }
                }
                QQC2.TextField {
                    Layout.fillWidth: true
                    text: actionRow.label
                    placeholderText: i18nd("dev.xarbit.appgrid", "Label")
                    onTextEdited: root._set(actionRow.index, "label", text)
                }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: root._remove(actionRow.index)
                    QQC2.ToolTip.text: i18nd("dev.xarbit.appgrid", "Remove action")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            // Row 2: command + run-in-terminal + placement.
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    Layout.fillWidth: true
                    text: actionRow.command
                    placeholderText: i18nd("dev.xarbit.appgrid", "Command, e.g. systemctl --user restart plasma-plasmashell")
                    onTextEdited: root._set(actionRow.index, "command", text)
                }
                QQC2.CheckBox {
                    text: i18nd("dev.xarbit.appgrid", "In terminal")
                    checked: actionRow.runInTerminal
                    onToggled: root._set(actionRow.index, "runInTerminal", checked)
                }
                PlacementSelector {
                    current: actionRow.placement
                    onPlacementChosen: placement => root._set(actionRow.index, "placement", placement)
                }
            }

            Kirigami.Separator { Layout.fillWidth: true; opacity: 0.3 }
        }
    }

    QQC2.Button {
        Layout.alignment: Qt.AlignLeft
        icon.name: "list-add"
        text: i18nd("dev.xarbit.appgrid", "Add custom action")
        onClicked: root._add()
    }
}
