/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared base for hover gates that must stand down briefly after a wheel
    event. Owns the grace clock so the concrete gates (HoverGate's cursor-
    motion filter, HoverActivation's dwell arming) don't each re-implement
    it. Inject clock in tests for deterministic timing.
*/

import QtQuick

QtObject {
    id: gate

    // How long after the last wheel event the grace window stays open.
    property int wheelGraceMs: 500

    // For tests: a function returning "now"; wall time when null.
    property var clock: null
    property double lastWheelTime: 0

    function now() {
        return clock !== null ? clock() : Date.now()
    }

    function markWheel() {
        lastWheelTime = now()
    }

    function withinWheelGrace() {
        return now() - lastWheelTime < wheelGraceMs
    }
}
