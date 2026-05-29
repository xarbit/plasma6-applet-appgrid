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

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: Kirigami.Units.iconSizes.smallMedium
        source: "search-symbolic"
        opacity: 0.5
    }

    PlasmaComponents.TextField {
        id: textField
        Layout.fillWidth: true
        placeholderText: i18nd("dev.xarbit.appgrid", "Search apps or type ? for commands")
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
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
            visible: textField.text.length > 0
            icon.name: "edit-clear"
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            onClicked: {
                textField.text = ""
                textField.forceActiveFocus()
            }
            Accessible.name: i18nd("dev.xarbit.appgrid", "Clear search")
        }
    }
}
