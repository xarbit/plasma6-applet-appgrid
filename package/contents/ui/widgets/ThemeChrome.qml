/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Draws the active Plasma theme's popup chrome (the `dialogs/background` SVG
    plus its dedicated drop shadow) for the center variant, so it looks and
    casts a shadow like Kickoff and other Plasma popups instead of a flat
    rectangle. The shadow is drawn in the SVG's own shadow margins so it spills
    outside the panel exactly as Plasma's does.

    Exposes the metrics the panel needs to align the rest of its chrome to the
    drawn SVG: `cornerRadius` (for the rounded-rect clip and blur region) and
    `hasThemeShadow` (so the panel drops its generic fallback shadow when the
    theme provides one). Both refresh on a live theme switch via the SVG's
    repaintNeeded signal. The corner radius is queried through `bridge` (see
    PlasmoidBridge) to keep this free of any direct Plasmoid dependency.
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

Item {
    id: root

    // PlasmoidBridge, used only for the theme corner-radius query.
    required property var bridge
    // Whether theme chrome is active (the "Use Plasma theme background" option).
    property bool active: false
    property real backgroundOpacity: 1

    // The Plasma theme popup-background SVG, the single source for both frames
    // and the corner query so they can never drift apart.
    readonly property string imagePath: "dialogs/background"

    // Bumped on a live theme switch (the frames re-emit repaintNeeded), which
    // re-runs the metric bindings below against the new theme.
    property int themeRevision: 0

    // Drawn corner radius of the theme background, in pixels (falls back to the
    // Kirigami default if the theme ships no rounded corner). 0 when inactive.
    readonly property int cornerRadius: {
        void themeRevision
        return active ? (bridge.themeBackgroundCornerRadius(imagePath) || Kirigami.Units.cornerRadius) : 0
    }

    // True when the theme provides its own dialog shadow (drawn here); the panel
    // then suppresses its generic fallback shadow.
    readonly property bool hasThemeShadow: {
        void themeRevision
        return active && shadowFrame.hasElementPrefix("shadow")
    }

    KSvg.FrameSvgItem {
        id: shadowFrame
        anchors.fill: parent
        anchors.leftMargin: -fixedMargins.left
        anchors.topMargin: -fixedMargins.top
        anchors.rightMargin: -fixedMargins.right
        anchors.bottomMargin: -fixedMargins.bottom
        imagePath: root.imagePath
        prefix: "shadow"
        visible: root.hasThemeShadow
        z: -1
        onRepaintNeeded: root.themeRevision++
    }

    KSvg.FrameSvgItem {
        anchors.fill: parent
        imagePath: root.imagePath
        visible: root.active
        opacity: root.backgroundOpacity
        onRepaintNeeded: root.themeRevision++
    }
}
