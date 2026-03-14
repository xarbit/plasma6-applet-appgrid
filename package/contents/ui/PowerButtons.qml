/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Power and session management buttons (Sleep, Restart, Shut Down, Session menu).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

RowLayout {
    id: powerButtons

    signal actionTriggered()

    spacing: Kirigami.Units.smallSpacing
    readonly property bool showLabels: Plasmoid.configuration.showActionLabels

    Repeater {
        model: [
            { icon: "system-suspend",  label: i18n("Sleep"),     action: function() { Plasmoid.sleep() } },
            { icon: "system-reboot",   label: i18n("Restart"),   action: function() { Plasmoid.restart() } },
            { icon: "system-shutdown", label: i18n("Shut Down"), action: function() { Plasmoid.shutDown() } },
        ]
        delegate: PlasmaComponents.ToolButton {
            required property var modelData
            icon.name: modelData.icon
            text: powerButtons.showLabels ? modelData.label : ""
            display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                             : PlasmaComponents.AbstractButton.IconOnly
            PlasmaComponents.ToolTip.text: modelData.label
            PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            onClicked: { modelData.action(); powerButtons.actionTriggered() }

            Accessible.name: modelData.label
            Accessible.role: Accessible.Button
        }
    }

    PlasmaComponents.ToolButton {
        id: sessionButton
        icon.name: "system-switch-user"
        text: powerButtons.showLabels ? i18n("Session") : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: i18n("Session")
        PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        checked: sessionMenu.visible
        onClicked: sessionMenu.visible ? sessionMenu.close() : sessionMenu.open()

        Accessible.name: i18n("Session")
        Accessible.role: Accessible.Button

        PlasmaComponents.Menu {
            id: sessionMenu
            y: sessionButton.height

            PlasmaComponents.MenuItem {
                icon.name: "system-lock-screen"
                text: i18n("Lock")
                onClicked: { Plasmoid.lock(); powerButtons.actionTriggered() }
                Accessible.name: i18n("Lock")
                Accessible.role: Accessible.MenuItem
            }
            PlasmaComponents.MenuItem {
                icon.name: "system-log-out"
                text: i18n("Log Out")
                onClicked: { Plasmoid.logOut(); powerButtons.actionTriggered() }
                Accessible.name: i18n("Log Out")
                Accessible.role: Accessible.MenuItem
            }
            PlasmaComponents.MenuItem {
                icon.name: "system-switch-user"
                text: i18n("Switch User")
                onClicked: { Plasmoid.switchUser(); powerButtons.actionTriggered() }
                Accessible.name: i18n("Switch User")
                Accessible.role: Accessible.MenuItem
            }
        }
    }
}
