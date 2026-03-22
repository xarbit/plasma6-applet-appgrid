/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

PlasmaComponents.ScrollView {
    id: fileBrowser

    property string path: ""
    property Item searchField: null

    signal fileOpened()
    signal directoryNavigated(string path)

    function focusList() { fileList.forceActiveFocus() }
    function activateCurrent() { fileList.activateCurrent() }

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

        function refresh() {
            var items = Plasmoid.listDirectory(fileBrowser.path)
            fileModel.clear()
            for (var i = 0; i < items.length; i++)
                fileModel.append(items[i])
            currentIndex = fileModel.count > 0 ? 0 : -1
        }

        Keys.onReturnPressed: activateCurrent()
        Keys.onEnterPressed: activateCurrent()
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Backspace && fileBrowser.searchField) {
                fileBrowser.searchField.forceActiveFocus()
                fileBrowser.searchField.text = fileBrowser.searchField.text.slice(0, -1)
                event.accepted = true
            } else if (event.text.length > 0 && !event.modifiers && fileBrowser.searchField) {
                fileBrowser.searchField.forceActiveFocus()
                fileBrowser.searchField.text += event.text
                event.accepted = true
            }
        }

        function activateCurrent() {
            if (currentIndex < 0 || currentIndex >= fileModel.count)
                return
            var item = fileModel.get(currentIndex)
            if (item.isDir) {
                fileBrowser.directoryNavigated(item.path + "/")
            } else {
                Qt.openUrlExternally("file://" + item.path)
                fileBrowser.fileOpened()
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
            target: fileBrowser
            function onPathChanged() { fileList.refresh() }
        }
    }
}
