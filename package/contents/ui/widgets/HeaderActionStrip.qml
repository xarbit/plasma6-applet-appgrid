/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Header action strip. Renders the configurable header actions (power,
    session, update) driven by the headerActions config: bar actions inline
    in display order, the rest behind a single overflow menu that hides when
    empty. Placement/order/enablement come from headeractions.js; this file
    owns the per-action icon/label/availability/trigger registry.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../js/headeractions.js" as HeaderActions

RowLayout {
    id: actions

    signal actionTriggered()
    function closeMenus() { if (overflowMenu) overflowMenu.close() }

    spacing: Kirigami.Units.smallSpacing

    required property bool showActionLabels
    // Ordered "id:placement" tokens; see headeractions.js.
    required property list<string> headerActions
    // Update-checker handle; null on distro packages and in tests.
    required property var updateChecker
    // Bridge to Plasma's session/power SPI — see SessionActions.qml.
    required property var sessionActions

    // Per-action presentation. Trigger + availability live in the functions
    // below since they depend on the live session/update state.
    readonly property var _meta: ({
        "updateCheck": { "icon": "system-software-update", "label": i18nd("dev.xarbit.appgrid", "Update available") },
        "sleep": { "icon": "system-suspend", "label": i18nd("dev.xarbit.appgrid", "Sleep") },
        "restart": { "icon": "system-reboot", "label": i18nd("dev.xarbit.appgrid", "Restart") },
        "shutdown": { "icon": "system-shutdown", "label": i18nd("dev.xarbit.appgrid", "Shut Down") },
        "lock": { "icon": "system-lock-screen", "label": i18nd("dev.xarbit.appgrid", "Lock") },
        "logout": { "icon": "system-log-out", "label": i18nd("dev.xarbit.appgrid", "Log Out") },
        "switchuser": { "icon": "system-switch-user", "label": i18nd("dev.xarbit.appgrid", "Switch User") }
    })

    function _available(id) {
        switch (id) {
        case "updateCheck":
            return !!updateChecker && updateChecker.enabled === true && updateChecker.hasUpdate === true
        case "sleep":      return sessionActions.canSuspend
        case "restart":    return sessionActions.canReboot
        case "shutdown":   return sessionActions.canShutdown
        case "lock":       return sessionActions.canLock
        case "logout":     return sessionActions.canLogout
        case "switchuser": return sessionActions.canSwitchUser
        }
        return false
    }

    function _run(id) {
        switch (id) {
        case "updateCheck": if (updateChecker) updateChecker.openReleasePage(); break
        case "sleep":      sessionActions.suspend(); break
        case "restart":    sessionActions.reboot(); break
        case "shutdown":   sessionActions.shutdown(); break
        case "lock":       sessionActions.lock(); break
        case "logout":     sessionActions.logout(); break
        case "switchuser": sessionActions.switchUser(); break
        }
        actions.actionTriggered()
    }

    readonly property var _parsed: HeaderActions.parse(headerActions, !!updateChecker)
    readonly property var barItems: _parsed.bar.filter(id => actions._available(id))
    readonly property var menuItems: _parsed.menu.filter(id => actions._available(id))

    // The live overflow menu, so closeMenus() can reach it.
    property var overflowMenu: null

    Repeater {
        model: actions.barItems
        delegate: PlasmaComponents.ToolButton {
            id: barButton
            required property string modelData
            readonly property bool isUpdate: modelData === "updateCheck"

            Layout.alignment: Qt.AlignVCenter
            icon.name: actions._meta[modelData].icon
            icon.color: isUpdate ? Kirigami.Theme.neutralTextColor : undefined
            text: actions.showActionLabels ? actions._meta[modelData].label : ""
            display: actions.showActionLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                              : PlasmaComponents.AbstractButton.IconOnly

            PlasmaComponents.ToolTip.text: barButton.isUpdate && actions.updateChecker
                ? i18nd("dev.xarbit.appgrid", "AppGrid %1 is available — click to view release notes",
                        actions.updateChecker.latestVersion)
                : actions._meta[modelData].label
            PlasmaComponents.ToolTip.visible: hovered && (!actions.showActionLabels || barButton.isUpdate)
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

            onClicked: actions._run(modelData)

            Accessible.name: actions._meta[modelData].label
            Accessible.role: Accessible.Button
        }
    }

    PlasmaComponents.ToolButton {
        id: menuButton
        visible: actions.menuItems.length > 0
        Layout.alignment: Qt.AlignVCenter
        icon.name: "overflow-menu"
        text: actions.showActionLabels ? i18nd("dev.xarbit.appgrid", "More") : ""
        display: actions.showActionLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                          : PlasmaComponents.AbstractButton.IconOnly
        checked: overflow.visible

        property bool _menuJustClosed: false
        Timer {
            id: reopenGuard
            interval: 300
            onTriggered: menuButton._menuJustClosed = false
        }

        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "More actions")
        PlasmaComponents.ToolTip.visible: !actions.showActionLabels && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        Accessible.name: i18nd("dev.xarbit.appgrid", "More actions")
        Accessible.role: Accessible.Button

        onClicked: if (!menuButton._menuJustClosed) overflow.open()

        PlasmaComponents.Menu {
            id: overflow
            y: menuButton.height
            x: menuButton.width - width

            Component.onCompleted: actions.overflowMenu = overflow
            Component.onDestruction: if (actions.overflowMenu === overflow) actions.overflowMenu = null

            onAboutToHide: {
                menuButton._menuJustClosed = true
                reopenGuard.restart()
            }

            Instantiator {
                model: actions.menuItems
                delegate: PlasmaComponents.MenuItem {
                    required property string modelData
                    icon.name: actions._meta[modelData].icon
                    text: actions._meta[modelData].label
                    onClicked: actions._run(modelData)
                }
                onObjectAdded: (idx, obj) => overflow.insertItem(idx, obj)
                onObjectRemoved: (idx, obj) => overflow.removeItem(obj)
            }
        }
    }
}
