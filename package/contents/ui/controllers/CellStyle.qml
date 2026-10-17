/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    How the launcher's views draw their cells and lists: icon size, label
    scale, hover effects, shadows, tooltips, badges, dividers, scroll bars.
    The panel builds one from its settings and every view and cell reads it,
    so a look setting is set in one place and passed as one object.
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../js/constants.js" as Const

QtObject {
    // Icon size in pixels.
    property real iconSize: Kirigami.Units.iconSizes.huge
    // Label font scale, following the size preset (Scale.textScale); 1.0 when
    // text size is decoupled from it (#167).
    property real fontScale: 1.0
    // The hover animation (Const.HoverAnimation).
    property int hoverAnimation: Const.HoverAnimation.None
    // The highlight slides between items only when animations are on.
    readonly property bool animateHighlight: hoverAnimation !== Const.HoverAnimation.None
    property bool shadowEnabled: false
    // Highlight the cell under the mouse (the keyboard cursor always shows).
    property bool hoverHighlight: true
    property bool showTooltips: true
    property bool showNewAppBadge: true
    property bool showDividers: true
    // The narrower (pre-#177) cell width, for a tighter grid.
    property bool reduceGridSpacing: false
    property bool showScrollbars: true
}
