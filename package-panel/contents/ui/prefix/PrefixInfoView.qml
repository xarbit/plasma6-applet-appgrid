/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

ColumnLayout {
    id: infoView

    property var sysInfo: Plasmoid.systemInfo()

    anchors.fill: parent
    anchors.margins: Kirigami.Units.largeSpacing * 2
    spacing: 0

    PlasmaComponents.Label {
        text: i18nd("dev.xarbit.appgrid", "System Information")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
    }

    Repeater {
        model: [
            { label: "AppGrid",  value: infoView.sysInfo.appgridVersion || "" },
            { label: "Variant",  value: infoView.sysInfo.variant || "" },
            { label: "Session",  value: infoView.sysInfo.sessionType || "" },
            { label: "Plasma",   value: infoView.sysInfo.plasmaVersion || "" },
            { label: "KF",       value: infoView.sysInfo.kfVersion || "" },
            { label: "Qt",       value: infoView.sysInfo.qtVersion || "" },
            { label: "OS",       value: infoView.sysInfo.os || "" },
            { label: "Screens",  value: infoView.sysInfo.screens || "" }
        ]

        delegate: Item {
            Layout.fillWidth: true
            implicitHeight: infoRow.implicitHeight + Kirigami.Units.largeSpacing * 2

            RowLayout {
                id: infoRow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: Kirigami.Units.largeSpacing

                PlasmaComponents.Label {
                    text: modelData.label
                    font.bold: true
                    opacity: 0.6
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                }

                PlasmaComponents.Label {
                    text: modelData.value
                    font.family: "monospace"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            Kirigami.Separator {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                opacity: 0.3
            }
        }
    }

    Item { Layout.fillHeight: true }

    PlasmaComponents.Button {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.largeSpacing
        icon.name: copyTimer.running ? "dialog-ok-apply" : "edit-copy"
        text: copyTimer.running
            ? i18nd("dev.xarbit.appgrid", "Copied!")
            : i18nd("dev.xarbit.appgrid", "Copy to Clipboard")
        onClicked: {
            var info = infoView.sysInfo
            var lines = [
                "AppGrid: " + (info.appgridVersion || ""),
                "Variant: " + (info.variant || ""),
                "Session: " + (info.sessionType || ""),
                "Plasma: " + (info.plasmaVersion || ""),
                "KF: " + (info.kfVersion || ""),
                "Qt: " + (info.qtVersion || ""),
                "OS: " + (info.os || ""),
                "Screens: " + (info.screens || "")
            ]
            infoClipboard.text = lines.join("\n")
            infoClipboard.selectAll()
            infoClipboard.copy()
            copyTimer.start()
        }

        Timer {
            id: copyTimer
            interval: 2000
        }

        TextEdit {
            id: infoClipboard
            visible: false
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        text: i18nd("dev.xarbit.appgrid", "Include this info when reporting issues on GitHub")
        font: Kirigami.Theme.smallFont
        opacity: 0.35
        horizontalAlignment: Text.AlignHCenter
    }
}
