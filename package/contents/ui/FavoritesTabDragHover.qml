/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Drag-hover tab switch for the Favorites tab button: when the user
    hovers a drag (own delegate or external .desktop file) over the button
    for ~600 ms, switch to the favorites tab so they can drop onto it.

    Drop in as a child of the tab button:

        PlasmaComponents.ToolButton {
            ...
            FavoritesTabDragHover { target: categoryBar }
        }
*/

import QtQuick
import org.kde.kirigami as Kirigami

DropArea {
    id: hover

    // The CategoryBar whose favoritesToggled(true) we call once the
    // dwell timer fires.
    required property var target

    // Dwell time before the tab switches — short enough to feel responsive,
    // long enough that a passing cursor doesn't trip it.
    property int dwellMs: 600

    anchors.fill: parent

    Timer {
        id: dwell
        interval: hover.dwellMs
        onTriggered: {
            if (!hover.target.favoritesActive)
                hover.target.favoritesToggled(true)
        }
    }

    onEntered: dwell.start()
    onExited: dwell.stop()

    // Refresh dwell on cursor movement so a stationary hover still fires
    // even if the drag system doesn't re-emit `entered` for sub-pixel moves.
    onPositionChanged: if (!dwell.running) dwell.restart()
}
