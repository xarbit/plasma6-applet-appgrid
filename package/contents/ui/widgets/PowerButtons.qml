/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Power and session buttons. The top-level slots (Sleep, Restart, Shut
    Down, Session) are ordered and individually shown/hidden via the
    powerButtonOrder / powerButtonsHidden config; the Session slot groups
    Lock / Log Out / Switch User in a dropdown.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.private.sessions as Sessions

import "../controllers"

RowLayout {
    id: powerButtons

    signal actionTriggered()
    function closeMenus() { if (_sessionMenu) _sessionMenu.close() }

    spacing: Kirigami.Units.smallSpacing

    ConfigCache { id: cfg; source: Plasmoid.configuration }

    readonly property alias showLabels: cfg.showActionLabels

    // The live Session dropdown, so closeMenus() can reach it.
    property var _sessionMenu: null

    Sessions.SessionManagement { id: sm }
    Sessions.SessionsModel { id: sessionsModel }

    readonly property alias hiddenButtons: cfg.powerButtonsHidden
    function isHidden(id) { return hiddenButtons.indexOf(id) >= 0 }

    readonly property list<string> defaultSlotOrder: ["sleep", "restart", "shutdown", "session"]

    // Top-level slots in configured order, hidden ones removed. An empty
    // config means "default order" (kcfg StringList defaults are unreliable).
    readonly property var orderedSlots: {
        const order = cfg.powerButtonOrder.length > 0
                      ? cfg.powerButtonOrder : defaultSlotOrder
        return order.filter(s => !isHidden(s))
    }

    readonly property var powerSlotInfo: ({
        "sleep":    { "icon": "system-suspend",  "label": i18nd("dev.xarbit.appgrid", "Sleep"),
                      "available": sm.canSuspend },
        "restart":  { "icon": "system-reboot",   "label": i18nd("dev.xarbit.appgrid", "Restart"),
                      "available": sm.canReboot },
        "shutdown": { "icon": "system-shutdown", "label": i18nd("dev.xarbit.appgrid", "Shut Down"),
                      "available": sm.canShutdown }
    })

    function runPowerSlot(id) {
        if (id === "sleep") sm.suspend()
        else if (id === "restart") sm.requestReboot()
        else if (id === "shutdown") sm.requestShutdown()
        powerButtons.actionTriggered()
    }

    function runSessionItem(id) {
        if (id === "lock") sm.lock()
        else if (id === "logout") sm.requestLogout()
        else if (id === "switchuser") sessionsModel.startNewSession(sessionsModel.shouldLock)
        powerButtons.actionTriggered()
    }

    // Update indicator — universal builds only, not part of the slot config.
    PlasmaComponents.ToolButton {
        id: updateButton
        visible: !!Plasmoid.updateChecker
                 && Plasmoid.updateChecker.enabled === true
                 && Plasmoid.updateChecker.hasUpdate === true
        icon.name: "system-software-update"
        icon.color: Kirigami.Theme.neutralTextColor
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

    Repeater {
        model: powerButtons.orderedSlots

        delegate: PlasmaComponents.ToolButton {
            id: slotButton
            required property string modelData

            property bool _menuJustClosed: false
            Timer {
                id: menuReopenGuard
                interval: 300
                onTriggered: slotButton._menuJustClosed = false
            }

            readonly property bool isSession: modelData === "session"
            readonly property var info: powerButtons.powerSlotInfo[modelData]
            readonly property bool lockShown: sm.canLock && !powerButtons.isHidden("lock")
            readonly property bool logoutShown: sm.canLogout && !powerButtons.isHidden("logout")
            readonly property bool switchShown: sessionsModel.canSwitchUser
                                                && !powerButtons.isHidden("switchuser")

            // Session items that should appear, in menu order.
            readonly property var sessionItems: {
                var items = []
                if (lockShown)
                    items.push({ "id": "lock", "icon": "system-lock-screen",
                                 "label": i18nd("dev.xarbit.appgrid", "Lock") })
                if (logoutShown)
                    items.push({ "id": "logout", "icon": "system-log-out",
                                 "label": i18nd("dev.xarbit.appgrid", "Log Out") })
                if (switchShown)
                    items.push({ "id": "switchuser", "icon": "system-switch-user",
                                 "label": i18nd("dev.xarbit.appgrid", "Switch User") })
                return items
            }

            // One session item left → render it as a direct button, no
            // dropdown; two or more → the "Session" button + menu.
            readonly property bool soloSession: isSession && sessionItems.length === 1
            readonly property bool useSessionMenu: isSession && sessionItems.length > 1
            readonly property string slotIcon:
                soloSession ? sessionItems[0].icon
                : isSession ? "system-log-out"
                : (info ? info.icon : "")
            readonly property string slotLabel:
                soloSession ? sessionItems[0].label
                : isSession ? i18nd("dev.xarbit.appgrid", "Session")
                : (info ? info.label : "")

            Layout.alignment: Qt.AlignVCenter
            visible: isSession ? (sessionItems.length > 0)
                               : (info !== undefined && info.available)
            icon.name: slotIcon
            text: powerButtons.showLabels ? slotLabel : ""
            display: powerButtons.showLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                             : PlasmaComponents.AbstractButton.IconOnly
            checked: useSessionMenu && sessionMenu.visible
            PlasmaComponents.ToolTip.text: slotLabel
            PlasmaComponents.ToolTip.visible: !powerButtons.showLabels && hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            onClicked: {
                if (soloSession)
                    powerButtons.runSessionItem(sessionItems[0].id)
                else if (useSessionMenu) {
                    // Open only if this click did not just dismiss the menu.
                    if (!slotButton._menuJustClosed)
                        sessionMenu.open()
                } else {
                    powerButtons.runPowerSlot(modelData)
                }
            }

            Accessible.name: slotLabel
            Accessible.role: Accessible.Button

            // Lives on every delegate but only used by the session slot.
            PlasmaComponents.Menu {
                id: sessionMenu
                y: slotButton.height
                // Right-aligned under the button so it opens into the app.
                x: slotButton.width - width

                Component.onCompleted: if (slotButton.isSession)
                                           powerButtons._sessionMenu = sessionMenu
                Component.onDestruction: if (powerButtons._sessionMenu === sessionMenu)
                                             powerButtons._sessionMenu = null

                // Fires the moment a dismiss begins (before the button's
                // click), so the click that closed the menu can't reopen it.
                onAboutToHide: {
                    slotButton._menuJustClosed = true
                    menuReopenGuard.restart()
                }

                // Instantiator removes a hidden item outright — a
                // visible:false MenuItem leaves a blank row in the menu.
                Instantiator {
                    model: slotButton.sessionItems
                    delegate: PlasmaComponents.MenuItem {
                        required property var modelData
                        icon.name: modelData.icon
                        text: modelData.label
                        onClicked: powerButtons.runSessionItem(modelData.id)
                    }
                    onObjectAdded: (idx, obj) => sessionMenu.insertItem(idx, obj)
                    onObjectRemoved: (idx, obj) => sessionMenu.removeItem(obj)
                }
            }
        }
    }
}
