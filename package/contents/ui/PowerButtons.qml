/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Power and session management buttons using Sessions.SessionManagement.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.private.sessions as Sessions

RowLayout {
    id: powerButtons

    signal actionTriggered()
    function closeMenus() { sessionMenu.close() }

    spacing: Kirigami.Units.smallSpacing
    readonly property bool showLabels: Plasmoid.configuration.showActionLabels

    // Update indicator — only present on universal builds (distro packages
    // surface their own update notifications via the system package manager).
    PlasmaComponents.ToolButton {
        id: updateButton
        visible: Plasmoid.updateChecker !== null
                 && Plasmoid.updateChecker.hasUpdate
        icon.name: "system-software-update"
        text: powerButtons.showLabels
              ? i18nd("dev.xarbit.appgrid", "Update available")
              : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: Plasmoid.updateChecker
            ? i18nd("dev.xarbit.appgrid", "AppGrid %1 is available — click to view release notes",
                    Plasmoid.updateChecker.latestVersion)
            : ""
        PlasmaComponents.ToolTip.visible: hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        onClicked: {
            if (Plasmoid.updateChecker)
                Plasmoid.updateChecker.openReleasePage()
            powerButtons.actionTriggered()
        }

        Accessible.name: i18nd("dev.xarbit.appgrid", "AppGrid update available")
        Accessible.role: Accessible.Button
    }

    Sessions.SessionManagement {
        id: sm
    }

    Sessions.SessionsModel {
        id: sessionsModel
    }

    // Primary buttons: Sleep, Restart, Shut Down
    PlasmaComponents.ToolButton {
        visible: sm.canSuspend
        icon.name: "system-suspend"
        text: powerButtons.showLabels ? i18nd("dev.xarbit.appgrid", "Sleep") : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Sleep")
        PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        onClicked: { sm.suspend(); powerButtons.actionTriggered() }
        Accessible.name: i18nd("dev.xarbit.appgrid", "Sleep")
        Accessible.role: Accessible.Button
    }

    PlasmaComponents.ToolButton {
        visible: sm.canReboot
        icon.name: "system-reboot"
        text: powerButtons.showLabels ? i18nd("dev.xarbit.appgrid", "Restart") : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Restart")
        PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        onClicked: { sm.requestReboot(); powerButtons.actionTriggered() }
        Accessible.name: i18nd("dev.xarbit.appgrid", "Restart")
        Accessible.role: Accessible.Button
    }

    PlasmaComponents.ToolButton {
        visible: sm.canShutdown
        icon.name: "system-shutdown"
        text: powerButtons.showLabels ? i18nd("dev.xarbit.appgrid", "Shut Down") : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Shut Down")
        PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        onClicked: { sm.requestShutdown(); powerButtons.actionTriggered() }
        Accessible.name: i18nd("dev.xarbit.appgrid", "Shut Down")
        Accessible.role: Accessible.Button
    }

    // Session menu: Lock, Log Out, Switch User
    PlasmaComponents.ToolButton {
        id: sessionButton
        visible: sm.canLock || sm.canLogout || sessionsModel.canSwitchUser
        icon.name: "system-log-out"
        text: powerButtons.showLabels ? i18nd("dev.xarbit.appgrid", "Session") : ""
        display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                         : PlasmaComponents.AbstractButton.IconOnly
        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "Session")
        PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        checked: sessionMenu.visible
        onClicked: sessionMenu.visible ? sessionMenu.close() : sessionMenu.open()

        Accessible.name: i18nd("dev.xarbit.appgrid", "Session")
        Accessible.role: Accessible.Button

        PlasmaComponents.Menu {
            id: sessionMenu
            y: sessionButton.height

            PlasmaComponents.MenuItem {
                visible: sm.canLock
                icon.name: "system-lock-screen"
                text: i18nd("dev.xarbit.appgrid", "Lock")
                onClicked: { sm.lock(); powerButtons.actionTriggered() }
            }

            PlasmaComponents.MenuItem {
                visible: sm.canLogout
                icon.name: "system-log-out"
                text: i18nd("dev.xarbit.appgrid", "Log Out")
                onClicked: { sm.requestLogout(); powerButtons.actionTriggered() }
            }

            PlasmaComponents.MenuItem {
                visible: sessionsModel.canSwitchUser
                icon.name: "system-switch-user"
                text: i18nd("dev.xarbit.appgrid", "Switch User")
                onClicked: { sessionsModel.startNewSession(sessionsModel.shouldLock); powerButtons.actionTriggered() }
            }
        }
    }
}
