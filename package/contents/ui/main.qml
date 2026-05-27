/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Root plasmoid item: panel icon + custom Window lifecycle.
    The window opens as a centered popup over a dim overlay; see GridWindow.qml.
*/

import QtQuick
import org.kde.plasma.plasmoid

import "controllers"
import "views"
import "js/migrations.js" as Migrations

PlasmoidItem {
    id: kicker

    compactRepresentation: compactRepresentationComponent
    fullRepresentation: Item {}
    preferredRepresentation: compactRepresentation

    activationTogglesExpanded: false

    ConfigCache { id: cfg; source: Plasmoid.configuration }

    Plasmoid.icon: cfg.useCustomButtonImage ? cfg.customButtonImage : cfg.icon

    property GridWindow gridWindow: null
    property bool gridOpen: false
    // Set while the window is being built asynchronously; see preloadWindow().
    property var _gridWindowIncubator: null

    // Shared drag source for all app drags — see DragSource.qml.
    readonly property alias dragSource: dragSourceImpl
    readonly property alias isDragInFlight: dragSourceImpl.isDragInFlight
    DragSource { id: dragSourceImpl }

    // Push config's opt-in into UpdateChecker (null on distro packages).
    Component.onCompleted: {
        Migrations.migrateLauncherIcon(Plasmoid.configuration)
        _syncUpdateChecker()
    }
    Connections {
        target: Plasmoid.configuration
        function onCheckForUpdatesChanged() { kicker._syncUpdateChecker() }
    }
    function _syncUpdateChecker() {
        if (Plasmoid.updateChecker)
            Plasmoid.updateChecker.enabled = cfg.checkForUpdates
    }

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {}
    }

    Connections {
        target: Plasmoid
        function onActivated() { kicker.toggleWindow() }
    }


    function destroyGridWindow() {
        if (_gridWindowIncubator)
            _gridWindowIncubator.forceCompletion()
        if (gridWindow) {
            gridWindow.visible = false
            gridWindow.destroy()
            gridWindow = null
        }
        gridOpen = false
    }

    function toggleWindow() {
        if (gridOpen) {
            closeWindow()
        } else {
            openWindow()
        }
    }

    // Build the window off the click path. Triggered by panel-icon hover, so
    // the tree is usually ready before the click; openWindow() forces the
    // build to finish if the click wins the race.
    function preloadWindow() {
        if (gridWindow || _gridWindowIncubator)
            return
        const incubator = gridWindowComponent.incubateObject(
            kicker, { appletInterface: kicker }, Qt.Asynchronous)
        if (incubator.status === Component.Ready) {
            gridWindow = incubator.object
            return
        }
        _gridWindowIncubator = incubator
        incubator.onStatusChanged = function(status) {
            if (status === Component.Ready) {
                kicker.gridWindow = incubator.object
                kicker._gridWindowIncubator = null
            }
        }
    }

    function openWindow() {
        gridOpen = true
        if (!gridWindow) {
            preloadWindow()
            if (_gridWindowIncubator)
                _gridWindowIncubator.forceCompletion()
        }
        gridWindow.showGrid()
    }

    function closeWindow() {
        gridOpen = false
        if (gridWindow)
            gridWindow.closeGrid()
    }

    Component {
        id: gridWindowComponent
        GridWindow {
            appsModel: Plasmoid.appsModel
            searchModel: Plasmoid.searchModel
            runnerSourceModel: Plasmoid.runnerSourceModel
            configuration: Plasmoid.configuration
            notifyAppLaunched: function(sid) { Plasmoid.notifyAppLaunched(sid) }
            runInTerminal: function(cmd, shell) { Plasmoid.runInTerminal(cmd, shell) }
            runCommand: function(cmd, shell) { Plasmoid.runCommand(cmd, shell) }
            runRunnerResult: function(idx) { return Plasmoid.runRunnerResult(idx) }
        }
    }
}
