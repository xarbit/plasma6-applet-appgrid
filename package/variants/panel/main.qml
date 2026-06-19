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
import "js/constants.js" as Const
import "js/migrations.js" as Migrations

PlasmoidItem {
    id: appgrid

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

    PlasmoidBridge { id: bridge }
    PlasmoidConfigSync {
        configuration: Plasmoid.configuration
        updateChecker: Plasmoid.updateChecker
        bridge: bridge
    }

    // "Pin to Task Manager" runs in-process via Kicker (needs this applet/corona).
    TaskManagerPinner { applet: appgrid }

    Component.onCompleted: {
        Migrations.migrateLauncherIcon(Plasmoid.configuration)
        // Move this applet's old per-applet hidden/recent/known/launch-count
        // lists into the shared store, so the panel and center share one list.
        Plasmoid.migrateLaunchState()
    }

    Plasmoid.icon: Plasmoid.configuration.useCustomButtonImage
        ? Plasmoid.configuration.customButtonImage
        : Plasmoid.configuration.icon

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {
            formFactor: Plasmoid.formFactor
            title: Plasmoid.title
            configuration: Plasmoid.configuration
            onActivated: Plasmoid.activated()
        }
    }

    Component {
        id: fullRepresentationComponent
        Views.GridPanel {
            id: panel
            appletInterface: appgrid
            appsModel: Plasmoid.appsModel
            searchModel: Plasmoid.searchModel
            runnerSourceModel: Plasmoid.runnerSourceModel
            configuration: Plasmoid.configuration
            plasmoidBridge: bridge
            updateChecker: Plasmoid.updateChecker
            favoritesClientInstance: Const.FAVORITES_CLIENT_ID
            sysInfo: Plasmoid.systemInfo()
            opacity: 1.0
            onCloseRequested: appgrid.expanded = false
            // The "settings" header action opens the applet's own Plasma config
            // dialog (the panel variant configures via System Settings) (#191).
            onConfigureRequested: Plasmoid.internalAction("configure").trigger()

            Connections {
                target: appgrid
                function onExpandedChanged() {
                    if (appgrid.expanded) {
                        panel.resetState()
                        if (Plasmoid.configuration.shakeOnOpen)
                            panel.shakeAllIcons()
                    } else {
                        panel.resetOnClose()
                        // Mirror Plasma's per-instance popupWidth/Height
                        // into our globalConfig so the user's chosen size
                        // survives an alternatives-switch from Kicker /
                        // Kickoff. See #87.
                        Plasmoid.persistPopupSize()
                    }
                }
            }

            Shortcut {
                sequence: "Escape"
                onActivated: appgrid.expanded = false
            }
        }
    }
}
