/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Power/session button editor, designed to drop into a Kirigami.FormLayout
    parent so it picks up the standard KCM column alignment. Emits `edited`
    with the new order and hidden-list whenever the user changes anything.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var buttonOrder: []
    property var hiddenButtons: []

    signal edited(var newOrder, var newHidden)

    spacing: Kirigami.Units.smallSpacing

    readonly property var slotLabels: ({
        "sleep": i18nd("dev.xarbit.appgrid", "Sleep"),
        "restart": i18nd("dev.xarbit.appgrid", "Restart"),
        "shutdown": i18nd("dev.xarbit.appgrid", "Shut Down"),
        "session": i18nd("dev.xarbit.appgrid", "Session"),
        "lock": i18nd("dev.xarbit.appgrid", "Lock"),
        "logout": i18nd("dev.xarbit.appgrid", "Log Out"),
        "switchuser": i18nd("dev.xarbit.appgrid", "Switch User")
    })

    readonly property var defaultSlotOrder: ["sleep", "restart", "shutdown", "session"]

    function _isHidden(id) {
        return (root.hiddenButtons || []).indexOf(id) >= 0
    }
    function _setHidden(id, hide) {
        var h = (root.hiddenButtons || []).slice()
        var i = h.indexOf(id)
        if (hide && i < 0)
            h.push(id)
        else if (!hide && i >= 0)
            h.splice(i, 1)
        root.edited(_currentOrder(), h)
    }

    // ListModel mirror — a StringList can't drive a Repeater directly.
    ListModel { id: orderModel }
    function _currentOrder() {
        var arr = []
        for (var i = 0; i < orderModel.count; i++)
            arr.push(orderModel.get(i).slotId)
        return arr
    }
    function _sameOrder(a, b) {
        if (a.length !== b.length)
            return false
        for (var i = 0; i < a.length; i++)
            if (a[i] !== b[i])
                return false
        return true
    }
    function _syncModel() {
        var target = (root.buttonOrder && root.buttonOrder.length > 0)
                     ? root.buttonOrder : defaultSlotOrder
        // Skip the rebuild when the model already matches — our own edits
        // round-trip back through cfg_, and clearing mid-drop makes the
        // reorder unreliable.
        if (_sameOrder(_currentOrder(), target))
            return
        orderModel.clear()
        for (var i = 0; i < target.length; i++)
            orderModel.append({ slotId: target[i] })
    }
    function _move(from, to) {
        orderModel.move(from, to, 1)
        root.edited(_currentOrder(), root.hiddenButtons)
    }
    onButtonOrderChanged: _syncModel()
    Component.onCompleted: _syncModel()

    Repeater {
        model: orderModel
        delegate: RowLayout {
            id: slotRow
            Layout.fillWidth: true
            required property int index
            required property string slotId
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                Layout.fillWidth: true
                text: root.slotLabels[slotRow.slotId] || slotRow.slotId
                checked: !root._isHidden(slotRow.slotId)
                onToggled: root._setHidden(slotRow.slotId, !checked)
            }
            QQC2.ToolButton {
                icon.name: "arrow-up"
                display: QQC2.AbstractButton.IconOnly
                enabled: slotRow.index > 0
                onClicked: root._move(slotRow.index, slotRow.index - 1)
            }
            QQC2.ToolButton {
                icon.name: "arrow-down"
                display: QQC2.AbstractButton.IconOnly
                enabled: slotRow.index < orderModel.count - 1
                onClicked: root._move(slotRow.index, slotRow.index + 1)
            }
        }
    }
}
