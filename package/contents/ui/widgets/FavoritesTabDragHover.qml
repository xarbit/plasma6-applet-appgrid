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

    // Own drag of an app that's already a favourite: re-adding it is a no-op, so
    // forbid the drop. Don't dwell-switch, reject here, and flag the shared drag
    // source so the #193 remove area stands down too — with nothing accepting
    // over the tab the platform shows the forbidden cursor and the drop cancels.
    function _blocked(drag) {
        return drag.source && drag.source.sourceStorageId
            && hover.target.isFavorite
            && hover.target.isFavorite(drag.source.sourceStorageId)
    }

    function _sync(drag) {
        if (_blocked(drag)) {
            dwell.stop()
            drag.source.blockedOnFavoritesTab = true
            drag.source.dropWillRemove = false
            drag.accepted = false
        } else if (!dwell.running) {
            // Refresh dwell on cursor movement so a stationary hover still fires
            // even if the drag system doesn't re-emit `entered` for sub-pixel moves.
            dwell.restart()
        }
    }

    onEntered: hover._sync(drag)
    onPositionChanged: hover._sync(drag)
    onExited: {
        dwell.stop()
        if (drag.source) drag.source.blockedOnFavoritesTab = false
    }
}
