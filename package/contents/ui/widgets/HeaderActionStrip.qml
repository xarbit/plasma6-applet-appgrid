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
import "../js/customheaderactions.js" as CustomHeaderActions

RowLayout {
    id: actions

    signal actionTriggered()
    // Emitted by the "settings" action; the host opens its settings surface.
    signal configureRequested()
    function closeMenus() { if (overflowMenu) overflowMenu.close() }

    // User-defined custom actions (#196). Raw config StringList (one JSON object
    // per entry); parsed/placed here so the host only forwards config + a runner.
    property var customHeaderActions: []
    // Bridge exposing runCommand(cmd, shell) / runInTerminal(cmd, shell); null in
    // tests, in which case custom actions render but do nothing on click.
    property var commandRunner: null
    // Shell passed to the runner, mirroring the t: prefix (cfg.terminalShell).
    property string terminalShell: ""
    // Freedesktop icon for the overflow (⋮) menu button; empty → default (#190).
    property string menuButtonIcon: ""

    readonly property var _customLayout: CustomHeaderActions.renderLayout(customHeaderActions)
    readonly property var customBarItems: _customLayout.bar
    readonly property var customMenuItems: _customLayout.menu

    function _runCustom(entry) {
        if (!entry || !entry.command)
            return
        if (commandRunner) {
            if (entry.runInTerminal)
                commandRunner.runInTerminal(entry.command, actions.terminalShell)
            else
                commandRunner.runCommand(entry.command, actions.terminalShell)
        }
        actions.actionTriggered()
    }

    // Whether the settings action can do anything (a host with no way to open
    // settings sets this false to drop the action). Both shipped variants can.
    property bool canConfigure: true

    spacing: Kirigami.Units.smallSpacing

    required property bool showActionLabels
    // When labels are on, the overflow ⋮ button can still be kept icon-only.
    property bool hideMenuButtonLabel: false
    readonly property bool _menuLabelVisible: showActionLabels && !hideMenuButtonLabel
    // Ordered "id:placement" tokens; see headeractions.js.
    required property list<string> headerActions
    // Update-checker handle; null on distro packages and in tests.
    required property var updateChecker
    // Bridge to Plasma's session/power SPI — see SessionActions.qml.
    required property var sessionActions

    // Per-action presentation. Trigger + availability live in the functions
    // below since they depend on the live session/update state.
    readonly property var _meta: ({
        "updateCheck": { "icon": HeaderActions.iconFor("updateCheck"), "label": i18nd("dev.xarbit.appgrid", "Update available") },
        "sleep": { "icon": HeaderActions.iconFor("sleep"), "label": i18nd("dev.xarbit.appgrid", "Sleep") },
        "hibernate": { "icon": HeaderActions.iconFor("hibernate"), "label": i18nd("dev.xarbit.appgrid", "Hibernate") },
        "restart": { "icon": HeaderActions.iconFor("restart"), "label": i18nd("dev.xarbit.appgrid", "Restart") },
        "shutdown": { "icon": HeaderActions.iconFor("shutdown"), "label": i18nd("dev.xarbit.appgrid", "Shut Down") },
        "lock": { "icon": HeaderActions.iconFor("lock"), "label": i18nd("dev.xarbit.appgrid", "Lock") },
        "logout": { "icon": HeaderActions.iconFor("logout"), "label": i18nd("dev.xarbit.appgrid", "Log Out") },
        "switchuser": { "icon": HeaderActions.iconFor("switchuser"), "label": i18nd("dev.xarbit.appgrid", "Switch User") },
        "settings": { "icon": HeaderActions.iconFor("settings"), "label": i18nd("dev.xarbit.appgrid", "Settings") }
    })

    // Live availability per action id. A binding (not a function) so barItems /
    // menuItems re-evaluate when a session capability or the update state flips.
    readonly property var _availability: ({
        "updateCheck": !!updateChecker && updateChecker.enabled === true && updateChecker.hasUpdate === true,
        "sleep": sessionActions.canSuspend,
        "hibernate": sessionActions.canHibernate,
        "restart": sessionActions.canReboot,
        "shutdown": sessionActions.canShutdown,
        "lock": sessionActions.canLock,
        "logout": sessionActions.canLogout,
        "switchuser": sessionActions.canSwitchUser,
        "settings": actions.canConfigure
    })

    function _run(id) {
        switch (id) {
        case "updateCheck": if (updateChecker) updateChecker.openReleasePage(); break
        case "sleep":      sessionActions.suspend(); break
        case "hibernate":  sessionActions.hibernate(); break
        case "restart":    sessionActions.reboot(); break
        case "shutdown":   sessionActions.shutdown(); break
        case "lock":       sessionActions.lock(); break
        case "logout":     sessionActions.logout(); break
        case "switchuser": sessionActions.switchUser(); break
        case "settings":   actions.configureRequested(); break
        }
        actions.actionTriggered()
    }

    readonly property var _layout: HeaderActions.layout(headerActions, !!updateChecker, _availability)
    readonly property var barItems: _layout.bar
    readonly property var menuItems: _layout.menu

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

    // Custom user actions placed on the bar, after the built-ins (#196).
    Repeater {
        model: actions.customBarItems
        delegate: PlasmaComponents.ToolButton {
            id: customBarButton
            required property var modelData
            readonly property string _label: CustomHeaderActions.displayLabel(modelData)

            Layout.alignment: Qt.AlignVCenter
            icon.name: modelData.icon
            text: actions.showActionLabels ? _label : ""
            display: actions.showActionLabels ? PlasmaComponents.AbstractButton.TextBesideIcon
                                              : PlasmaComponents.AbstractButton.IconOnly

            PlasmaComponents.ToolTip.text: customBarButton._label
            PlasmaComponents.ToolTip.visible: hovered && !actions.showActionLabels
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

            onClicked: actions._runCustom(modelData)

            Accessible.name: customBarButton._label
            Accessible.role: Accessible.Button
        }
    }

    PlasmaComponents.ToolButton {
        id: menuButton
        visible: actions.menuItems.length > 0 || actions.customMenuItems.length > 0
        Layout.alignment: Qt.AlignVCenter
        icon.name: actions.menuButtonIcon || HeaderActions.MENU_BUTTON_DEFAULT_ICON
        text: actions._menuLabelVisible ? i18nd("dev.xarbit.appgrid", "More") : ""
        display: actions._menuLabelVisible ? PlasmaComponents.AbstractButton.TextBesideIcon
                                           : PlasmaComponents.AbstractButton.IconOnly
        checked: overflow.visible

        property bool _menuJustClosed: false
        Timer {
            id: reopenGuard
            interval: 300
            onTriggered: menuButton._menuJustClosed = false
        }

        PlasmaComponents.ToolTip.text: i18nd("dev.xarbit.appgrid", "More actions")
        PlasmaComponents.ToolTip.visible: !actions._menuLabelVisible && hovered
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        Accessible.name: i18nd("dev.xarbit.appgrid", "More actions")
        Accessible.role: Accessible.Button

        onClicked: if (!menuButton._menuJustClosed) overflow.open()

        AppGridMenu {
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

            // Custom user actions placed in the overflow menu, after built-ins.
            Instantiator {
                model: actions.customMenuItems
                delegate: PlasmaComponents.MenuItem {
                    required property var modelData
                    icon.name: modelData.icon
                    text: CustomHeaderActions.displayLabel(modelData)
                    onClicked: actions._runCustom(modelData)
                }
                onObjectAdded: (idx, obj) => overflow.insertItem(actions.menuItems.length + idx, obj)
                onObjectRemoved: (idx, obj) => overflow.removeItem(obj)
            }
        }
    }
}
