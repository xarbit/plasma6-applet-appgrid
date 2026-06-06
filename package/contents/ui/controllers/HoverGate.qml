/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Decides whether a HoverHandler.pointChanged event should trigger a
    hover-select. pointChanged also fires on click button-state updates
    and on rows scrolling under a stationary cursor — both are rejected
    via a position cache. The wheel grace (highlight follows the cursor
    while wheel-scrolling) comes from WheelGraceGate.

    State is kept inside the gate so the algorithm is testable in
    isolation without standing up a full ListView + HoverHandler.
*/

import QtQuick

WheelGraceGate {
    id: gate

    // Last cursor scene-position seen by allows(); -1 is the sentinel
    // for "no event yet observed since reset".
    property point lastHoverPos: Qt.point(-1, -1)

    // Drop cached state — call when results change so a stationary
    // cursor over the new top row doesn't auto-claim the highlight.
    function reset() {
        lastHoverPos = Qt.point(-1, -1)
    }

    // Returns true if the caller should accept the hover-select. The
    // anchor advances on accept only — updating on every event would
    // reset the reference per pointChanged and let sub-pixel drift on a
    // fractionally-scaled screen stay under the 1 px threshold forever,
    // never crossing into a select (#145). Sentinel still consumes its
    // first event by anchoring, so a stationary cursor doesn't auto-
    // claim the highlight on launcher open.
    function allows(scenePos) {
        if (!withinWheelGrace()) {
            if (lastHoverPos.x < 0) {
                lastHoverPos = scenePos
                return false
            }
            const samePos = Math.abs(scenePos.x - lastHoverPos.x) < 1
                         && Math.abs(scenePos.y - lastHoverPos.y) < 1
            if (samePos)
                return false
        }
        lastHoverPos = scenePos
        return true
    }
}
