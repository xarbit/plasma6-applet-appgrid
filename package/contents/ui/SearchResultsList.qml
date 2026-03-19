/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Unified search results list — renders app results and KRunner results
    in a single ListView with continuous keyboard navigation.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

ListView {
    id: listView

    property PlasmaComponents.TextField searchField: null
    property real iconSize: Kirigami.Units.iconSizes.huge

    signal launched(int index)
    signal contextMenuRequested(int index, string storageId, string desktopFile)

    clip: true
    currentIndex: count > 0 ? 0 : -1
    highlightMoveDuration: 0

    // Track mouse movement to prevent hover stealing focus when results appear under cursor
    property bool mouseMovedSinceReset: false
    onCountChanged: mouseMovedSinceReset = false

    Keys.onReturnPressed: if (currentIndex >= 0) listView.launched(currentIndex)
    Keys.onEnterPressed: if (currentIndex >= 0) listView.launched(currentIndex)

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
            currentIndex = 0
    }

    Keys.onBacktabPressed: {
        if (currentIndex > 0)
            currentIndex--
        else
            currentIndex = count - 1
    }

    Keys.onEscapePressed: {
        if (searchField) searchField.forceActiveFocus()
    }

    delegate: Column {
        width: listView.width

        // Section divider between app results and runner results
        Rectangle {
            width: parent.width
            height: model.isSectionBoundary ? 1 : 0
            color: Plasmoid.configuration.showDividers !== false
                   ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                   : "transparent"
        }

        PlasmaComponents.ItemDelegate {
            id: resultDelegate
            width: listView.width
            height: listView.iconSize + Kirigami.Units.smallSpacing * 2
            highlighted: listView.currentIndex === model.index

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                // Alt+number shortcut badge
                Rectangle {
                    visible: model.shortcutNumber > 0
                    implicitWidth: shortcutLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
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
                        id: shortcutLabel
                        anchors.centerIn: parent
                        text: "Alt+" + model.shortcutNumber
                        font.bold: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }

                    Accessible.ignored: true
                }

                Kirigami.Icon {
                    implicitWidth: listView.iconSize
                    implicitHeight: listView.iconSize
                    source: model.iconName || "application-x-executable"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: model.name || ""
                            elide: Text.ElideRight
                            color: resultDelegate.highlighted
                                   ? Kirigami.Theme.highlightedTextColor
                                   : Kirigami.Theme.textColor
                        }
                        Rectangle {
                            implicitWidth: typeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            implicitHeight: typeLabel.implicitHeight + Kirigami.Units.smallSpacing
                            radius: Kirigami.Units.cornerRadius
                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                           Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b, 0.08)

                            PlasmaComponents.Label {
                                id: typeLabel
                                anchors.centerIn: parent
                                text: model.category || i18nd("dev.xarbit.appgrid", "Application")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                        }
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: model.subtext || ""
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                        visible: text.length > 0
                        color: resultDelegate.highlighted
                               ? Kirigami.Theme.highlightedTextColor
                               : Kirigami.Theme.textColor
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (!listView.mouseMovedSinceReset)
                        listView.mouseMovedSinceReset = true
                    else
                        listView.currentIndex = model.index
                }
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton)
                        listView.contextMenuRequested(model.index, model.storageId || "", model.desktopFile || "")
                    else
                        listView.launched(model.index)
                }

                Accessible.name: (model.shortcutNumber > 0 ? "Alt+" + model.shortcutNumber + ": " : "") + (model.name || "")
                Accessible.role: Accessible.Button
                Accessible.description: model.subtext || ""
                Accessible.focusable: true
            }
        }
    }
}
