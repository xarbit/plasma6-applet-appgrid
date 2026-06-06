/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Tracks which item a dwell-to-activate gesture has armed. The caller
    drives a timer: enter() arms an item and asks for a (re)start, leave()
    disarms it and asks for a stop. State lives here so the enter/leave
    race — and the wheel-vs-hover cross-fire — are testable without
    standing up the hovered widgets. Wheel grace comes from WheelGraceGate.
*/

WheelGraceGate {
    id: gate

    // When false, enter() is a no-op — nothing ever arms.
    property bool enabled: false

    // The armed item; "" when nothing is pending.
    property string pending: ""

    // Arm name. Returns true if the caller should (re)start its timer.
    // Suppressed while disabled or a wheel happened within the grace.
    function enter(name) {
        if (!enabled)
            return false
        if (withinWheelGrace())
            return false
        pending = name
        return true
    }

    // Disarm name. Returns true if the caller should stop its timer.
    // Only the armed item may cancel: moving straight from one item to the
    // next can deliver the new item's enter before the old item's leave, so
    // a blind cancel would wipe the selection the new item just armed.
    function leave(name) {
        if (pending !== name)
            return false
        pending = ""
        return true
    }

    // Open the suppression window and drop any in-flight dwell. Used both for
    // a wheel (don't activate the tab sliding under a stationary cursor) and
    // for entering the bar from outside (don't activate a tab merely crossed).
    function suppress() {
        markWheel()
        pending = ""
    }

    function clear() {
        pending = ""
    }
}
