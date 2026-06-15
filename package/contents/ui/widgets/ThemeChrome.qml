/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Draws the active Plasma theme's popup chrome (the `dialogs/background` SVG and
    its `shadow` prefix) for the center variant, so it matches Kickoff and other
    Plasma popups instead of a flat rectangle.

    Both frames are drawn directly, the way Plasma's own ToolTip composes a themed
    surface in-scene: the background FrameSvgItem paints the theme's rounded,
    antialiased corner art itself, and a shadow-prefix FrameSvgItem behind it is
    pushed outward by its own margins so the soft shadow spills around the
    background. No texture capture / mask effects (those aliased the corner and
    risked binding loops) and no window setMask / KWindowShadow (a window-level
    feature we can't use inside a full-screen overlay that also holds the dim
    layer).

    Note: themes that draw a square frame and round only via their mask prefix
    (applied by the compositor for real Dialog windows) will show square corners
    here, since we render the frame art directly. The common art-rounded themes
    (Breeze etc.) round correctly.

    Exposes `cornerRadius` (used by the panel for the blur/contrast region) and
    `hasThemeShadow` (so the panel drops its generic fallback shadow when the
    theme provides one), refreshed on a live theme switch. Only the background
    frame bumps `themeRevision`, so the metric bindings can't drive a repaint
    loop. The radius is queried through `bridge` (see PlasmoidBridge) to keep this
    free of any direct Plasmoid dependency.
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

    // The Plasma theme popup-background SVG.
    readonly property string imagePath: "dialogs/background"

    // Bumped when the background SVG reloads (a live theme switch), re-running
    // the metric bindings against the new theme.
    property int themeRevision: 0

    // Drawn corner radius of the theme background, in pixels (falls back to the
    // Kirigami default if the theme ships no rounded corner). 0 when inactive.
    readonly property int cornerRadius: {
        void themeRevision
        return active ? (bridge.themeBackgroundCornerRadius(imagePath) || Kirigami.Units.cornerRadius) : 0
    }

    // True when the theme ships a dialog shadow (drawn below); the panel then
    // suppresses its own generic fallback shadow.
    readonly property bool hasThemeShadow: {
        void themeRevision
        return active && shadowFrame.hasElementPrefix("shadow")
    }

    // Theme drop shadow, in-scene the way Plasma's ToolTip draws it: a
    // shadow-prefix frame pushed outward by its own margins so the soft shadow
    // spills around the rounded background and hugs its corner.
    KSvg.FrameSvgItem {
        id: shadowFrame
        anchors.fill: backgroundFrame
        anchors.topMargin: -margins.top
        anchors.leftMargin: -margins.left
        anchors.rightMargin: -margins.right
        anchors.bottomMargin: -margins.bottom
        imagePath: root.imagePath
        prefix: "shadow"
        visible: root.hasThemeShadow
    }

    KSvg.FrameSvgItem {
        id: backgroundFrame
        anchors.fill: parent
        imagePath: root.imagePath
        opacity: root.backgroundOpacity
        visible: root.active
        onRepaintNeeded: root.themeRevision++
    }
}
