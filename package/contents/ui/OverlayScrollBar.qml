/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Vertical scroll bar for the grid / list flickables. Attached directly
    to a Flickable so it overlays the content and reserves no layout width
    — a bar appearing then cannot change the grid width and feed back into
    column sizing, which could otherwise oscillate into a freeze (#110).
    Shown only while scrolling or hovered; hidden when idle.
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid

PlasmaComponents.ScrollBar {
    policy: Plasmoid.configuration.showScrollbars !== false
            ? PlasmaComponents.ScrollBar.AsNeeded
            : PlasmaComponents.ScrollBar.AlwaysOff

    opacity: active || hovered ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation { duration: Kirigami.Units.shortDuration }
    }
}
