/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

TestCase {
    id: tst_WheelGraceGate
    name: "WheelGraceGate"

    property var fakeNow: 100000

    function gate() {
        var c = Qt.createComponent("WheelGraceGate.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, {
            clock: function() { return tst_WheelGraceGate.fakeNow }
        })
    }

    function test_idleIsNotInGrace() {
        var g = gate()
        verify(!g.withinWheelGrace(), "no wheel yet → not in grace")
    }

    function test_markWheelOpensGrace() {
        var g = gate()
        g.markWheel()
        verify(g.withinWheelGrace(), "just after a wheel → in grace")
    }

    function test_graceExpires() {
        var g = gate()
        g.markWheel()
        tst_WheelGraceGate.fakeNow += g.wheelGraceMs
        verify(!g.withinWheelGrace(), "at the grace boundary → no longer in grace")
    }
}
