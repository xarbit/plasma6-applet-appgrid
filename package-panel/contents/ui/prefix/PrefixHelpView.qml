/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    anchors.fill: parent
    anchors.margins: Kirigami.Units.largeSpacing * 2
    spacing: 0

    PlasmaComponents.Label {
        text: i18nd("dev.xarbit.appgrid", "Quick Commands")
        font.bold: true
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
        Layout.bottomMargin: Kirigami.Units.largeSpacing * 2
    }

    Repeater {
        model: [
            { section: i18nd("dev.xarbit.appgrid", "Run") },
            { prefix: "t:", icon: "utilities-terminal", title: i18nd("dev.xarbit.appgrid", "Terminal"), example: "t:htop" },
            { prefix: ":",  icon: "system-run",         title: i18nd("dev.xarbit.appgrid", "Run Command"), example: ":xdg-open ." },

            { section: i18nd("dev.xarbit.appgrid", "Browse") },
            { prefix: "/",  icon: "folder-open",        title: i18nd("dev.xarbit.appgrid", "Browse Files"), example: "/usr/bin" },
            { prefix: "~/", icon: "folder-home",        title: i18nd("dev.xarbit.appgrid", "Browse Home"), example: "~/Documents" },

            { section: i18nd("dev.xarbit.appgrid", "Tools") },
            { prefix: "i:", icon: "documentinfo",       title: i18nd("dev.xarbit.appgrid", "System Info"), example: "i:" },
            { prefix: "h:", icon: "view-hidden",        title: i18nd("dev.xarbit.appgrid", "Hidden Apps"), example: "h:" },
            { prefix: "?",  icon: "help-hint",          title: i18nd("dev.xarbit.appgrid", "This Help"), example: "" }
        ]

        delegate: Item {
            Layout.fillWidth: true
            implicitHeight: modelData.section
                ? sectionLabel.implicitHeight + Kirigami.Units.largeSpacing * 2
                : commandRow.implicitHeight + Kirigami.Units.largeSpacing * 2

            PlasmaComponents.Label {
                id: sectionLabel
                visible: !!modelData.section
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    bottomMargin: Kirigami.Units.smallSpacing
                }
                text: modelData.section || ""
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
                opacity: 0.4
                font.capitalization: Font.AllUppercase
            }

            RowLayout {
                id: commandRow
                visible: !modelData.section
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                    source: modelData.icon || ""
                    opacity: 0.6
                }

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
                        text: modelData.prefix || ""
                        font.family: "monospace"
                        font.bold: true
                    }
                }

                PlasmaComponents.Label {
                    text: modelData.title || ""
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    visible: (modelData.example || "").length > 0
                    text: modelData.example || ""
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.4
                }
            }

            Kirigami.Separator {
                visible: !modelData.section
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                opacity: 0.3
            }
        }
    }

    Item { Layout.fillHeight: true }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        text: i18nd("dev.xarbit.appgrid", "Alt+1\u2009\u2013\u2009Alt+9 launches search results instantly")
        font: Kirigami.Theme.smallFont
        opacity: 0.35
        horizontalAlignment: Text.AlignHCenter
    }
}
