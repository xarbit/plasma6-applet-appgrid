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

    Component.onCompleted: Migrations.migrateLauncherIcon(Plasmoid.configuration)

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
            nativePopup: true
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

            // On Wayland resetState()'s focus request can land before the popup
            // window is mapped and active, and is lost when Plasma activates it.
            // Re-assert search focus once the window is active — once per open,
            // not on every re-activation, so closing a context menu doesn't pull
            // focus from the grid back to the search field (#213).
            property bool _focusSearchOnActivate: false

            function _onOpened() {
                panel.resetState()
                if (Plasmoid.configuration.shakeOnOpen)
                    panel.shakeAllIcons()
                panel._focusSearchOnActivate = !(panel.Window.window && panel.Window.window.active)
            }

            // The full representation is created lazily on the first expand,
            // possibly after expandedChanged already fired (#213).
            Component.onCompleted: {
                if (appgrid.expanded)
                    panel._onOpened()
            }

            Connections {
                target: panel.Window.window
                function onActiveChanged() {
                    if (panel._focusSearchOnActivate && panel.Window.window.active) {
                        panel._focusSearchOnActivate = false
                        panel.focusSearchField()
                    }
                }
            }

            Connections {
                target: appgrid
                function onExpandedChanged() {
                    if (appgrid.expanded) {
                        panel._onOpened()
                    } else {
                        panel._focusSearchOnActivate = false
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
