/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Single Plasmoid-callback surface. Wraps every Plasmoid.Q_INVOKABLE
    that QML needs, so the two variant main.qml files don't each
    redeclare a dozen forwarding lambdas, GridWindow/GridPanel hold
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

    function notifyAppLaunched(sid)         { Plasmoid.notifyAppLaunched(sid) }
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

    // -- Window-management glue, used by GridWindow.qml --
    function configureWindow(window)                       { Plasmoid.configureWindow(window) }
    function updateWindowScreen(window, useActiveScreen)   { Plasmoid.updateWindowScreen(window, useActiveScreen) }
    function targetScreenGeometry(useActiveScreen)         { return Plasmoid.targetScreenGeometry(useActiveScreen) }
    function setBackgroundEffects(window, blur, contrast, x, y, w, h, radius, useThemeMask) { Plasmoid.setBackgroundEffects(window, blur, contrast, x, y, w, h, radius, useThemeMask) }
    function setInputRect(window, x, y, w, h)              { Plasmoid.setInputRect(window, x, y, w, h) }
    function themeBackgroundCornerRadius(imagePath)       { return Plasmoid.themeBackgroundCornerRadius(imagePath) }
    function windowDevicePixelRatio(window)               { return Plasmoid.windowDevicePixelRatio(window) }
}
