/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Single Plasmoid-callback surface. Wraps every Plasmoid.Q_INVOKABLE
    that QML needs, so the variant main.qml files don't each
    redeclare a dozen forwarding lambdas, GridPanel holds
    one bridge property instead of a fan of `required property var`
    slots, and tests can inject a plain QtObject stub with the same
    method names.

    Pure functions only — non-invokable data (config, models,
    updateChecker, etc.) stays on its own property since each has a
    distinct lifecycle.
*/

import QtQuick
import org.kde.plasma.plasmoid

QtObject {
    readonly property bool isWayland: Plasmoid.isWayland
    // The shared favourites-folder model (appgridrc, global across variants); the
    // grid binds folders through it. Without this forward the plasmoid variants
    // get null and never show folders the standalone window created (#18).
    readonly property var favoritesGroupedModel: Plasmoid.favoritesGroupedModel

    function notifyAppLaunched(sid)         { Plasmoid.notifyAppLaunched(sid) }
    function addToTaskManager(desktopFile)  { Plasmoid.addToTaskManager(desktopFile) }
    function addToDesktop(desktopFile)      { Plasmoid.addToDesktop(desktopFile) }
    function canPinToTaskManager()          { return Plasmoid.canPinToTaskManager() }
    function canAddToDesktop()              { return Plasmoid.canAddToDesktop() }
    function runInTerminal(cmd, shell)      { Plasmoid.runInTerminal(cmd, shell) }
    function runCommand(cmd, shell)         { Plasmoid.runCommand(cmd, shell) }
    function runRunnerResult(idx)           { return Plasmoid.runRunnerResult(idx) }
    function runRunnerAction(idx, actIdx)   { return Plasmoid.runRunnerAction(idx, actIdx) }
    function runnerSubstitutionText(idx)    { return Plasmoid.runnerSubstitutionText(idx) }
    function appActions(sid)                { return Plasmoid.appActions(sid) }
    function launchAppAction(sid, idx)      { Plasmoid.launchAppAction(sid, idx) }
    function canManageInDiscover(sid)       { return Plasmoid.canManageInDiscover(sid) }
    function openInDiscover(sid)            { Plasmoid.openInDiscover(sid) }
    function listDirectory(path)            { return Plasmoid.listDirectory(path) }
    function setSearchUsesFrecency(on)      { Plasmoid.setSearchUsesFrecency(on) }
    function setSearchShowsHidden(on)       { Plasmoid.setSearchShowsHidden(on) }
    function setActivityScopingEnabled(on)  { Plasmoid.setActivityScopingEnabled(on) }
}
