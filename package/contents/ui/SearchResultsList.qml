/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    List view for search results with keyboard navigation and number shortcuts.
    Press Alt+1 through Alt+9 to quickly launch a result (COSMIC-style).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ListView {
    id: listView

    // The search field to redirect typing to.
    property PlasmaComponents.TextField searchField: null

    signal launched(int index)
    signal navigatedPastEnd()

    clip: true
    currentIndex: 0
    boundsBehavior: Flickable.StopAtBounds
    highlight: Rectangle {
        color: Kirigami.Theme.highlightColor
        radius: Kirigami.Units.cornerRadius
    }
    highlightMoveDuration: 0

    Keys.onReturnPressed: if (currentIndex >= 0) listView.launched(currentIndex)
    Keys.onEnterPressed: if (currentIndex >= 0) listView.launched(currentIndex)

    // Redirect typing back to search field.
    Keys.onPressed: function(event) {
        // Alt+1 through Alt+9 shortcuts
        if (event.modifiers & Qt.AltModifier) {
            var num = event.key - Qt.Key_0
            if (num >= 1 && num <= 9 && num <= listView.count) {
                listView.launched(num - 1)
                event.accepted = true
                return
            }
        }

        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            searchField.forceActiveFocus()
            searchField.text = searchField.text.slice(0, -1)
            event.accepted = true
        } else if (event.text.length > 0 && !event.modifiers) {
            searchField.forceActiveFocus()
            searchField.text += event.text
            event.accepted = true
        }
    }

    Keys.onDownPressed: {
        if (currentIndex < count - 1)
            currentIndex++
        else
            listView.navigatedPastEnd()
    }

    Keys.onUpPressed: {
        if (currentIndex > 0)
            currentIndex--
        else if (searchField)
            searchField.forceActiveFocus()
    }

    Keys.onTabPressed: {
        if (currentIndex < count - 1)
            currentIndex++
        else
            listView.navigatedPastEnd()
    }

    Keys.onBacktabPressed: {
        if (currentIndex > 0)
            currentIndex--
        else if (searchField)
            searchField.forceActiveFocus()
    }

    delegate: PlasmaComponents.ItemDelegate {
        id: listDelegate
        width: listView.width
        height: Kirigami.Units.iconSizes.huge + Kirigami.Units.smallSpacing * 2
        highlighted: listView.currentIndex === model.index

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            // Shortcut badge (Alt+1 through Alt+9)
            Rectangle {
                visible: model.index < 9
                implicitWidth: Kirigami.Units.gridUnit * 1.5
                implicitHeight: Kirigami.Units.gridUnit * 1.5
                radius: Kirigami.Units.cornerRadius
                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                               Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.2)

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: String(model.index + 1)
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                }

                Accessible.ignored: true
            }

            Kirigami.Icon {
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                source: model.iconName || "application-x-executable"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: model.name || ""
                    elide: Text.ElideRight
                    color: listDelegate.highlighted
                           ? Kirigami.Theme.highlightedTextColor
                           : Kirigami.Theme.textColor
                }

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: model.genericName || ""
                    elide: Text.ElideRight
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    visible: text.length > 0
                    color: listDelegate.highlighted
                           ? Kirigami.Theme.highlightedTextColor
                           : Kirigami.Theme.textColor
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: listView.currentIndex = model.index
            onClicked: listView.launched(model.index)

            Accessible.name: (model.index < 9 ? i18n("Alt+%1: ", model.index + 1) : "") + (model.name || "")
            Accessible.role: Accessible.Button
            Accessible.description: model.genericName || ""
            Accessible.focusable: true
        }
    }
}
