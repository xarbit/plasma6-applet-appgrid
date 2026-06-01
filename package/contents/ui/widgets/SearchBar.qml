/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Borderless search field with icon at the top of the grid.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: searchBar

    property alias text: textField.text
    property alias field: textField
    // External gate for the clear button — caller can hide it while
    // the layout around the search field is still settling (so the X
    // doesn't appear to slide in from the right with the field).
    property bool clearButtonEnabled: true
    // Scaler applied to Kirigami.Theme.defaultFont.pointSize for the
    // search field. Caller derives it from icon size so the placeholder
    // stays in proportion with grid labels.
    required property real fontScale

    signal accepted()
    signal moveDown()
    signal moveUp()
    signal tabPressed()
    signal pageUp()
    signal pageDown()
    signal home()
    signal end()
    signal altNumberPressed(int number)
    signal altLetterPressed(int key)

    // Empties the field and returns focus to it. Single entry point so the
    // clear button and the Escape shortcut stay in lock-step.
    function clear() {
        textField.text = ""
        textField.forceActiveFocus()
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
        implicitHeight: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
        source: "search-symbolic"
        opacity: 0.5
    }

    PlasmaComponents.TextField {
        id: textField
        Layout.fillWidth: true
        placeholderText: i18nd("dev.xarbit.appgrid", "Search apps or type ? for commands")
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * searchBar.fontScale
        background: Item {}
        color: Kirigami.Theme.textColor
        placeholderTextColor: Qt.rgba(
            Kirigami.Theme.textColor.r,
            Kirigami.Theme.textColor.g,
            Kirigami.Theme.textColor.b, 0.4)

        Keys.onReturnPressed: searchBar.accepted()
        Keys.onEnterPressed: searchBar.accepted()
        Keys.onDownPressed: searchBar.moveDown()
        Keys.onUpPressed: searchBar.moveUp()
        Keys.onTabPressed: searchBar.tabPressed()
        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_PageUp:   searchBar.pageUp();   event.accepted = true; return
            case Qt.Key_PageDown: searchBar.pageDown(); event.accepted = true; return
            case Qt.Key_Home:     searchBar.home();     event.accepted = true; return
            case Qt.Key_End:      searchBar.end();      event.accepted = true; return
            }
            if (event.modifiers & Qt.AltModifier) {
                var num = event.key - Qt.Key_0
                if (num >= 1 && num <= 9) {
                    searchBar.altNumberPressed(num)
                    event.accepted = true
                } else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                    searchBar.altLetterPressed(event.key)
                    event.accepted = true
                }
            }
        }

        Accessible.name: i18nd("dev.xarbit.appgrid", "Search applications")
        Accessible.role: Accessible.EditableText
        Accessible.searchEdit: true

        PlasmaComponents.ToolButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: textField.text.length > 0 && searchBar.clearButtonEnabled
            icon.name: "edit-clear"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            onClicked: searchBar.clear()
            PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Clear search")
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            Accessible.name: i18nd("dev.xarbit.appgrid", "Clear search")
        }
    }
}
