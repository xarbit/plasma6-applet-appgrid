/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Bridge to Plasma's private kicker SPI for actions that touch other
    surfaces (Task Manager, Desktop) or invoke external editors. Kept
    out of the widgets so AppContextMenu (and any future caller) stays
    free of Plasma::Private imports and is testable with a plain stub.
*/

import QtQuick
import org.kde.plasma.private.kicker as Kicker

QtObject {
    id: bridge

    required property var applet

    function pinToTaskManager(desktopFile) {
        _ci.addLauncher(applet, Kicker.ContainmentInterface.TaskManager, desktopFile)
    }
    function addToDesktop(desktopFile) {
        _ci.addLauncher(applet, Kicker.ContainmentInterface.Desktop, desktopFile)
    }
    // KMenuEdit takes either an app storage id or a menu group path — same
    // call, the editor figures out the type. Empty string opens at root.
    function editMenuItem(itemId) {
        _runner.runMenuEditor(itemId || "")
    }

    // Typed as `var` — namespaced typenames trip QML 2's strict
    // property-type check ("ProcessRunner* is not the same type as
    // Kicker.ProcessRunner") even though they refer to the same C++ class.
    readonly property var _runner: Kicker.ProcessRunner {}
    readonly property var _ci: Kicker.ContainmentInterface {}
}
