/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    A category bar scroll arrow, in the margin reserved at one edge of the tab
    strip. It pages on click and, with open-on-hover on, after a dwell and then
    on a slow repeat while the cursor rests on it. It fades out (rather than
    hiding) when its side has nothing to scroll, so the strip's layout settles
    smoothly.
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.ToolButton {
    id: root

    // The CategoryBar this arrow scrolls.
    required property var bar

    focusPolicy: Qt.NoFocus
    property bool scrollable: false
    // Each arrow supplies its page function; invoked on click and, with
    // open-on-hover on, after a dwell and then on a slow repeat while hovered.
    property var pageAction: null
    // Open-on-hover arming. Set when the cursor enters and cleared on each
    // fire, so the dwell timer pages exactly once per arming; the retrigger
    // timer re-arms it every few seconds while the cursor rests on the arrow.
    property bool _hoverArmed: false

    // Page, then (open-on-hover) schedule a slow re-arm so a resting cursor
    // keeps paging every hoverRetriggerInterval rather than racing to the end.
    function _page() {
        if (pageAction)
            pageAction()
        _hoverArmed = false
        if (root.bar.openOnHover)
            retriggerTimer.restart()
    }

    onHoveredChanged: {
        _hoverArmed = hovered
        if (!hovered)
            retriggerTimer.stop()
    }
    onClicked: _page()
    enabled: scrollable
    // Fixed-size button sitting in the reserved margin at a catFlick edge (its
    // instance anchors it). Fades out when its side has nothing to scroll;
    // hidden at opacity 0 so it never eats clicks meant for the categories.
    opacity: scrollable ? 1 : 0
    visible: opacity > 0
    z: 1
    // implicitWidth, not width: each instance anchors top/bottom + one side, so
    // width is free and takes this — and it avoids qmllint's layout-managed-width
    // warning that a bare width: triggers on a ToolButton.
    implicitWidth: root.bar.scrollArrowWidth
    icon.width: root.bar.buttonIconSize
    icon.height: root.bar.buttonIconSize

    Behavior on opacity {
        NumberAnimation { duration: Kirigami.Units.shortDuration }
    }

    // Tooltip mirrors the accessible name each instance sets (#171).
    PlasmaComponents.ToolTip.text: Accessible.name
    PlasmaComponents.ToolTip.visible: hovered && scrollable
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay

    // Dwell: while armed, page once after a short delay so merely sweeping
    // the cursor across the arrow doesn't page. repeat:false alone wouldn't
    // stop it — the running binding stays true while hovered and would
    // restart it — so _hoverArmed gates the binding and the fire clears it.
    Timer {
        running: root.bar.openOnHover && root.hovered && root._hoverArmed
            && root.scrollable && root.pageAction !== null
        interval: root.bar.hoverPageDwell
        repeat: false
        onTriggered: root._page()
    }

    // Slow re-arm: hoverRetriggerInterval after a page, re-arm the dwell if
    // the cursor still rests on the (still-scrollable) arrow, so paging
    // continues hands-free without racing to the end.
    Timer {
        id: retriggerTimer
        interval: root.bar.hoverRetriggerInterval
        repeat: false
        onTriggered: if (root.bar.openOnHover && root.hovered && root.scrollable)
            root._hoverArmed = true
    }

    Accessible.role: Accessible.Button
}
