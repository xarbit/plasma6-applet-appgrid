/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    View for prefix mode commands: help, terminal, shell command, file browser.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

Item {
    id: prefixView

    property string mode: ""       // "help", "terminal", "command", "files"
    property string argument: ""   // text after the prefix
    property Item searchField: null

    signal commandExecuted()
    signal fileOpened()
    signal directoryNavigated(string path)

    function focusFileList() {
        fileList.forceActiveFocus()
    }

    function activateFileCurrent() {
        fileList.activateCurrent()
    }

    // -- Help mode --
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 2
        visible: prefixView.mode === "help"
        spacing: 0

        // Header
        PlasmaComponents.Label {
            text: i18n("Quick Commands")
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
            Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
        }

        // Command list
        Repeater {
            model: [
                { prefix: "t:", icon: "utilities-terminal", title: i18n("Terminal"), example: "t:htop" },
                { prefix: ":",  icon: "system-run",         title: i18n("Run Command"), example: ":xdg-open ." },
                { prefix: "/",  icon: "folder-open",        title: i18n("Browse Files"), example: "/usr/bin" },
                { prefix: "~/", icon: "folder-home",        title: i18n("Browse Home"), example: "~/Documents" },
                { prefix: "?",  icon: "help-hint",          title: i18n("This Help"), example: "" }
            ]

            delegate: Item {
                Layout.fillWidth: true
                implicitHeight: commandRow.implicitHeight + Kirigami.Units.largeSpacing * 2

                RowLayout {
                    id: commandRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: Kirigami.Units.iconSizes.smallMedium
                        source: modelData.icon
                        opacity: 0.6
                    }

                    // Prefix badge
                    Rectangle {
                        implicitWidth: Math.max(Kirigami.Units.gridUnit * 2.5,
                                                prefixText.implicitWidth + Kirigami.Units.largeSpacing)
                        implicitHeight: prefixText.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.cornerRadius
                        color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                       Kirigami.Theme.highlightColor.g,
                                       Kirigami.Theme.highlightColor.b, 0.15)

                        PlasmaComponents.Label {
                            id: prefixText
                            anchors.centerIn: parent
                            text: modelData.prefix
                            font.family: "monospace"
                            font.bold: true
                        }
                    }

                    PlasmaComponents.Label {
                        text: modelData.title
                        Layout.fillWidth: true
                    }

                    // Example
                    PlasmaComponents.Label {
                        visible: modelData.example.length > 0
                        text: modelData.example
                        font.family: "monospace"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.4
                    }
                }

                // Bottom separator
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Qt.rgba(Kirigami.Theme.textColor.r,
                                   Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.06)
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Keyboard tip
        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Alt+1\u2009\u2013\u2009Alt+9 launches search results instantly")
            font: Kirigami.Theme.smallFont
            opacity: 0.35
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // -- Terminal / Command hint --
    ColumnLayout {
        anchors.centerIn: parent
        visible: prefixView.mode === "terminal" || prefixView.mode === "command"
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Kirigami.Units.iconSizes.huge
            implicitHeight: Kirigami.Units.iconSizes.huge
            source: prefixView.mode === "terminal" ? "utilities-terminal" : "system-run"
            opacity: 0.5
        }

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (prefixView.argument.trim().length === 0)
                    return prefixView.mode === "terminal"
                        ? i18n("Type a command to run in terminal")
                        : i18n("Type a command to execute")
                return prefixView.mode === "terminal"
                    ? i18n("Press Enter to run in terminal")
                    : i18n("Press Enter to execute")
            }
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
            opacity: 0.7
        }

        PlasmaComponents.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: prefixView.argument.trim().length > 0
            text: prefixView.argument.trim()
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            opacity: 0.9
        }
    }

    // -- File browser --
    PlasmaComponents.ScrollView {
        anchors.fill: parent
        visible: prefixView.mode === "files"
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        ListView {
            id: fileList
            clip: true
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0

            highlight: Rectangle {
                color: Kirigami.Theme.highlightColor
                radius: Kirigami.Units.cornerRadius
            }

            model: ListModel { id: fileModel }

            property string currentPath: ""

            function refresh() {
                var items = Plasmoid.listDirectory(prefixView.argument)
                fileModel.clear()
                for (var i = 0; i < items.length; i++)
                    fileModel.append(items[i])
                currentIndex = fileModel.count > 0 ? 0 : -1
            }

            Keys.onReturnPressed: activateCurrent()
            Keys.onEnterPressed: activateCurrent()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace && prefixView.searchField) {
                    prefixView.searchField.forceActiveFocus()
                    prefixView.searchField.text = prefixView.searchField.text.slice(0, -1)
                    event.accepted = true
                } else if (event.text.length > 0 && !event.modifiers && prefixView.searchField) {
                    prefixView.searchField.forceActiveFocus()
                    prefixView.searchField.text += event.text
                    event.accepted = true
                }
            }

            function activateCurrent() {
                if (currentIndex < 0 || currentIndex >= fileModel.count)
                    return
                var item = fileModel.get(currentIndex)
                if (item.isDir) {
                    prefixView.directoryNavigated(item.path + "/")
                } else {
                    Plasmoid.openFile(item.path)
                    prefixView.fileOpened()
                }
            }

            delegate: PlasmaComponents.ItemDelegate {
                id: fileDelegate
                width: fileList.width
                height: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
                highlighted: fileList.currentIndex === model.index

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                        source: model.icon || "application-x-generic"
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: model.name || ""
                        elide: Text.ElideRight
                        color: fileDelegate.highlighted
                               ? Kirigami.Theme.highlightedTextColor
                               : Kirigami.Theme.textColor
                    }

                    PlasmaComponents.Label {
                        visible: model.isDir
                        text: ">"
                        opacity: 0.4
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: fileList.currentIndex = model.index
                    onClicked: fileList.activateCurrent()
                }
            }

            Connections {
                target: prefixView
                function onArgumentChanged() {
                    if (prefixView.mode === "files")
                        fileList.refresh()
                }
                function onModeChanged() {
                    if (prefixView.mode === "files")
                        fileList.refresh()
                }
            }
        }
    }
}
