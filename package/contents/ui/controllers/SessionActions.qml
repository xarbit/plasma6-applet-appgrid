/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Bridge to Plasma's private sessions SPI. Wraps SessionManagement +
    SessionsModel so widgets that need power/session capabilities (e.g.
    HeaderActionStrip) consume reactive bool properties + trigger
    methods, and stay free of org.kde.plasma.private.sessions imports
    (testable with a plain QtObject stub).
*/

import QtQuick
import org.kde.plasma.private.sessions as Sessions

QtObject {
    id: actions

    readonly property bool canSuspend: _sm.canSuspend
    readonly property bool canReboot: _sm.canReboot
    readonly property bool canShutdown: _sm.canShutdown
    readonly property bool canLock: _sm.canLock
    readonly property bool canLogout: _sm.canLogout
    readonly property bool canSwitchUser: _sessions.canSwitchUser

    function suspend()    { _sm.suspend() }
    function reboot()     { _sm.requestReboot() }
    function shutdown()   { _sm.requestShutdown() }
    function lock()       { _sm.lock() }
    function logout()     { _sm.requestLogout() }
    function switchUser() { _sessions.startNewSession(_sessions.shouldLock) }

    // See LauncherActions.qml — `var` avoids the namespaced-typename
    // mismatch QML 2's strict property check raises.
    readonly property var _sm: Sessions.SessionManagement {}
    readonly property var _sessions: Sessions.SessionsModel {}
}
