/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Decides whether a HoverHandler.pointChanged event should trigger a
    hover-select. pointChanged also fires on click button-state updates
    and on rows scrolling under a stationary cursor — both are rejected
    via a position cache. Wheel events flip an override so the highlight
    follows the cursor while the user is actively wheel-scrolling.

    State is kept inside the gate so the algorithm is testable in
    isolation without standing up a full ListView + HoverHandler.
*/

import QtQuick

QtObject {
    id: gate

    // How long after the last wheel event the cursor-motion gate is
    // bypassed (highlight follows cursor even with stationary mouse).
    property int wheelGraceMs: 500

    // Last cursor scene-position seen by allows(); -1 is the sentinel
    // for "no event yet observed since reset".
    property point _lastHoverPos: Qt.point(-1, -1)
    property double _lastWheelTime: 0

    // For tests: lets the suite inject a fake clock without monkey-
    // patching Date.now. Falls through to real wall time when null.
    property var clock: null

    function _now() {
        return clock !== null ? clock() : Date.now()
    }

    // Hook the wheel handler to this on every event.
    function markWheel() {
        _lastWheelTime = _now()
    }

    // Drop cached state — call when results change so a stationary
    // cursor over the new top row doesn't auto-claim the highlight.
    function reset() {
        _lastHoverPos = Qt.point(-1, -1)
    }

    // Returns true if the caller should accept the hover-select. The
    // anchor advances on accept only — updating on every event would
    // reset the reference per pointChanged and let sub-pixel drift on a
    // fractionally-scaled screen stay under the 1 px threshold forever,
    // never crossing into a select (#145). Sentinel still consumes its
    // first event by anchoring, so a stationary cursor doesn't auto-
    // claim the highlight on launcher open.
    function allows(scenePos) {
        const wheelActive = _now() - _lastWheelTime < wheelGraceMs
        if (!wheelActive) {
            if (_lastHoverPos.x < 0) {
                _lastHoverPos = scenePos
                return false
            }
            const samePos = Math.abs(scenePos.x - _lastHoverPos.x) < 1
                         && Math.abs(scenePos.y - _lastHoverPos.y) < 1
            if (samePos)
                return false
        }
        _lastHoverPos = scenePos
        return true
    }
}
