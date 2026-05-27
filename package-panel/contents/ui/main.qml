/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Root plasmoid item: panel icon + native Plasma popup.
    Opens near the panel icon, like Kickoff.
*/

import QtQuick
import org.kde.plasma.plasmoid

import "controllers"
import "views" as Views
import "js/migrations.js" as Migrations

PlasmoidItem {
    id: kicker

    compactRepresentation: compactRepresentationComponent
    fullRepresentation: fullRepresentationComponent
    preferredRepresentation: compactRepresentation

    activationTogglesExpanded: true
    // Keep the popup open while a drag-out is in flight so the source surface
    // doesn't disappear mid-drag (which would cancel the platform DnD before
    // the drop target accepts it).
    hideOnWindowDeactivate: !isDragInFlight

    // Shared drag source for all app drags — see DragSource.qml.
    readonly property alias dragSource: dragSourceImpl
    readonly property alias isDragInFlight: dragSourceImpl.isDragInFlight
    DragSource { id: dragSourceImpl }

    // Update checker (universal builds only) — see standalone main.qml.
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
            Plasmoid.updateChecker.enabled = Plasmoid.configuration.checkForUpdates === true
    }

    Plasmoid.icon: Plasmoid.configuration.useCustomButtonImage
        ? Plasmoid.configuration.customButtonImage
        : Plasmoid.configuration.icon

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {}
    }

    Component {
        id: fullRepresentationComponent
        Views.GridPanel {
            id: panel
            nativePopup: true
            appletInterface: kicker
            appsModel: Plasmoid.appsModel
            searchModel: Plasmoid.searchModel
            runnerSourceModel: Plasmoid.runnerSourceModel
            configuration: Plasmoid.configuration
            notifyAppLaunched: function(sid) { Plasmoid.notifyAppLaunched(sid) }
            runInTerminal: function(cmd, shell) { Plasmoid.runInTerminal(cmd, shell) }
            runCommand: function(cmd, shell) { Plasmoid.runCommand(cmd, shell) }
            runRunnerResult: function(idx) { return Plasmoid.runRunnerResult(idx) }
            opacity: 1.0
            onCloseRequested: kicker.expanded = false

            Connections {
                target: kicker
                function onExpandedChanged() {
                    if (kicker.expanded) {
                        panel.resetState()
                        if (Plasmoid.configuration.shakeOnOpen)
                            panel.shakeAllIcons()
                    } else {
                        panel.resetOnClose()
                    }
                }
            }

            Shortcut {
                sequence: "Escape"
                onActivated: kicker.expanded = false
            }
        }
    }
}
