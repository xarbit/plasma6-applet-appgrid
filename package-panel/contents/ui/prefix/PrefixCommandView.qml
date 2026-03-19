/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

ColumnLayout {
    id: commandView

    property string mode: "terminal"   // "terminal" or "command"
    property string argument: ""

    anchors.centerIn: parent
    spacing: Kirigami.Units.largeSpacing

    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Kirigami.Units.iconSizes.huge
        implicitHeight: Kirigami.Units.iconSizes.huge
        source: commandView.mode === "terminal" ? "utilities-terminal" : "system-run"
        opacity: 0.5
    }

    PlasmaComponents.Label {
        Layout.alignment: Qt.AlignHCenter
        text: {
            if (commandView.argument.trim().length === 0)
                return commandView.mode === "terminal"
                    ? i18nd("dev.xarbit.appgrid", "Type a command to run in terminal")
                    : i18nd("dev.xarbit.appgrid", "Type a command to execute")
            return commandView.mode === "terminal"
                ? i18nd("dev.xarbit.appgrid", "Press Enter to run in terminal")
                : i18nd("dev.xarbit.appgrid", "Press Enter to execute")
        }
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        opacity: 0.7
    }

    PlasmaComponents.Label {
        Layout.alignment: Qt.AlignHCenter
        visible: commandView.argument.trim().length > 0
        text: commandView.argument.trim()
        font.family: "monospace"
        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
        opacity: 0.9
    }
}
