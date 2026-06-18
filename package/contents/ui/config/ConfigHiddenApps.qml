/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigHiddenAppsContent. The body manages
    its own scrollable list, so an AbstractKCM (no built-in flickable) hosts it
    and lets it fill the page.

    Deliberate exception to the cfg_ buffering restored on the other pages (#191):
    hiddenApps writes go straight to Plasmoid.configuration (live). This is an
    action list, not a form — the launcher's right-click "Unhide" mutates the same
    Plasmoid.configuration.hiddenApps, and the live binding keeps the list in sync
    reactively without the page's former Connections re-pull (#162). Buffering it
    would both desync that and risk clobbering a concurrent launcher hide on Apply.
*/

import QtQuick

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

KCM.AbstractKCM {
    id: page

    framedView: false

    ConfigHiddenAppsContent {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        configuration: Plasmoid.configuration
        appsModel: Plasmoid.appsModel
    }
}
