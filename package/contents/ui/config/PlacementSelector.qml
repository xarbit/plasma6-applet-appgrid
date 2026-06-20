/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Segmented Bar / Menu / Off placement selector, shared by the built-in
    header-action editor (HeaderActionsConfig) and the custom-action editor
    (CustomHeaderActionsEditor) so the placement vocabulary lives in one place.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

RowLayout {
    id: root

    // The currently-selected placement ("bar" | "menu" | "off").
    property string current
    signal placementChosen(string placement)

    spacing: 0

    readonly property var _order: ["bar", "menu", "off"]
    readonly property var _label: ({
        "bar": i18nd("dev.xarbit.appgrid", "Bar"),
        "menu": i18nd("dev.xarbit.appgrid", "Menu"),
        "off": i18nd("dev.xarbit.appgrid", "Off")
    })

    Repeater {
        model: root._order
        delegate: QQC2.Button {
            required property string modelData
            text: root._label[modelData]
            flat: root.current !== modelData
            highlighted: root.current === modelData
            onClicked: root.placementChosen(modelData)
        }
    }
}
