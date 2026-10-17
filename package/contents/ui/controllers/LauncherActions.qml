/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Context-menu actions that touch other Plasma surfaces (Task Manager,
    Desktop) or invoke external editors. "Pin to Task Manager" goes through
    the controller's plasmoidClient — in-process in the panel applet, over
    D-Bus to a center plasmoid from the standalone daemon, since Kicker's
    ContainmentInterface needs a live applet + corona. "Add to Desktop" goes
    through its systemActions.
    KMenuEdit is just a process launch, so it stays on Kicker's ProcessRunner.
*/

import QtQuick
import org.kde.plasma.private.kicker as Kicker

QtObject {
    id: root

    // The controller's plasmoidClient and systemActions; null without the
    // C++ plugin (tests).
    property var taskManager: null
    property var desktop: null

    function pinToTaskManager(desktopFile) {
        if (desktopFile && root.taskManager)
            root.taskManager.addToTaskManager(desktopFile)
    }
    function addToDesktop(desktopFile) {
        if (desktopFile && root.desktop)
            root.desktop.addToDesktop(desktopFile)
    }
    // Capability probes — the menu hides actions that would no-op. Default true
    // without the services (test stubs).
    function canPinToTaskManager() {
        return root.taskManager ? root.taskManager.canPinToTaskManager() : true
    }
    function canAddToDesktop() {
        return root.desktop ? root.desktop.canAddToDesktop() : true
    }
    // KMenuEdit takes either an app storage id or a menu group path — same
    // call, the editor figures out the type. Empty string opens at root.
    function editMenuItem(itemId) {
        _runner.runMenuEditor(itemId || "")
    }

    // Typed as `var` — namespaced typenames trip QML 2's strict
    // property-type check even though they refer to the same C++ class.
    readonly property var _runner: Kicker.ProcessRunner {}
}
