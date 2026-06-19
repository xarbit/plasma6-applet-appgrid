/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigHiddenAppsContent. The body manages
    its own scrollable list, so an AbstractKCM (no built-in flickable) hosts it
    and lets it fill the page.

    Deliberate exception to the cfg_ buffering restored on the other pages (#191):
    hidden-app writes go straight to the live model (Plasmoid.appsModel), not a
    buffer. This is an action list, not a form — the launcher's right-click
    "Unhide" mutates the same model, the live binding keeps the list in sync, and
    AppGridController persists every change to the shared LaunchStateStore
    (appgridrc) so the panel and center variants share one hidden-apps list (#191).
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
        appsModel: Plasmoid.appsModel
    }
}
