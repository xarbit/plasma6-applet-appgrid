/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Root plasmoid item for the center variant: just the panel icon. Activating it
    toggles the standalone `appgrid` daemon's window over D-Bus (launching the
    daemon if needed) — the launcher window runs in its own process so KWin can
    animate it with any window open/close effect, like KRunner. See src/standalone
    and AppGridPlugin::toggleStandaloneWindow().
*/

import QtQuick
import org.kde.plasma.plasmoid

import "controllers"
import "js/migrations.js" as Migrations

PlasmoidItem {
    id: appgrid

    compactRepresentation: compactRepresentationComponent
    fullRepresentation: Item {}
    preferredRepresentation: compactRepresentation

    activationTogglesExpanded: false

    // The launcher's settings live in its own window (the daemon): opened from
    // the gear in the launcher header, or the "Configure Launcher…" button on the
    // General tab of this plasmoid's Plasma config (ConfigButton.qml). No separate
    // context-menu entry — Plasma's own "Configure AppGrid…" covers the applet.

    ConfigCache { id: cfg; source: Plasmoid.configuration }

    Plasmoid.icon: cfg.useCustomButtonImage ? cfg.customButtonImage : cfg.icon

    // Mirror the panel button's appearance into the D-Bus helper so the daemon's
    // settings window can show + edit it (icon + text label) when this plasmoid
    // is present (#191). Recomputes whenever any of the four config values change.
    readonly property var buttonAppearance: ({
        "icon": Plasmoid.configuration.icon,
        // Stringify: customButtonImage is a url, which has no D-Bus type — a raw
        // QUrl in the a{sv} map breaks marshalling.
        "customButtonImage": String(Plasmoid.configuration.customButtonImage),
        "useCustomButtonImage": Plasmoid.configuration.useCustomButtonImage,
        "menuLabel": Plasmoid.configuration.menuLabel
    })
    onButtonAppearanceChanged: Plasmoid.updateButtonAppearanceCache(buttonAppearance)

    // The daemon settings window pushed a new appearance back — write it into the
    // applet config (live button update + persistence).
    Connections {
        target: Plasmoid
        function onSetButtonAppearanceRequested(values) {
            if (values.icon !== undefined)
                Plasmoid.configuration.icon = values.icon
            if (values.customButtonImage !== undefined)
                Plasmoid.configuration.customButtonImage = values.customButtonImage
            if (values.useCustomButtonImage !== undefined)
                Plasmoid.configuration.useCustomButtonImage = values.useCustomButtonImage
            if (values.menuLabel !== undefined)
                Plasmoid.configuration.menuLabel = values.menuLabel
        }
    }

    Component.onCompleted: {
        Migrations.migrateLauncherIcon(Plasmoid.configuration)
        // One-shot: hand the user's existing settings to the daemon's appgridrc.
        Plasmoid.migrateConfigToStandalone()
        Plasmoid.updateButtonAppearanceCache(buttonAppearance)
    }

    Component {
        id: compactRepresentationComponent
        CompactRepresentation {
            formFactor: Plasmoid.formFactor
            title: Plasmoid.title
            configuration: Plasmoid.configuration
            onActivated: Plasmoid.toggleStandaloneWindow()
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() { Plasmoid.toggleStandaloneWindow() }
    }

    // Runs the daemon's "Pin to Task Manager" in this applet's process (it has the
    // corona Kicker needs); the daemon reaches us via the plasmoid D-Bus helper.
    TaskManagerPinner { applet: appgrid }
}
