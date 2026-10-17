/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

TestCase {
    name: "HoverGate"

    property var fakeNow: 1000

    function gate() {
        var c = Qt.createComponent("../../package/contents/ui/controllers/HoverGate.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        // Inject the fake clock so wheel-grace timing is deterministic.
        return c.createObject(null, {
            clock: function() { return fakeNow }
        })
    }

    // --- Sentinel / first event ---

    function test_firstEventRejected() {
        var g = gate()
        verify(!g.allows(Qt.point(100, 100)),
               "first hover event after reset should not select")
    }

    function test_resetReturnsToSentinel() {
        var g = gate()
        g.allows(Qt.point(100, 100))      // consume sentinel
        verify(g.allows(Qt.point(200, 200))) // motion accepted
        g.reset()
        verify(!g.allows(Qt.point(300, 300)),
               "after reset, the next event is the new sentinel")
    }

    // --- Cursor motion ---

    function test_motionAccepted() {
        var g = gate()
        g.allows(Qt.point(100, 100))      // sentinel
        verify(g.allows(Qt.point(110, 100)),
               "non-trivial motion should select")
    }

    function test_samePixelRejected() {
        var g = gate()
        g.allows(Qt.point(100, 100))      // sentinel
        verify(g.allows(Qt.point(110, 100)))
        verify(!g.allows(Qt.point(110, 100)),
               "identical scenePos (e.g. a click event) should not select")
    }

    function test_subPixelJitterRejected() {
        var g = gate()
        g.allows(Qt.point(100, 100))
        g.allows(Qt.point(110, 100))
        verify(!g.allows(Qt.point(110.5, 100.2)),
               "sub-pixel drift counts as a click, not motion")
    }

    function test_slowMotionAccumulates() {
        // Anchor must NOT advance on rejected events; otherwise sub-pixel
        // steps reset the reference each call and a slow drag stays under
        // the threshold forever — the #145 regression.
        var g = gate()
        g.allows(Qt.point(100, 100))            // sentinel
        verify(!g.allows(Qt.point(100.3, 100))) // < 1 px → reject, anchor stays
        verify(!g.allows(Qt.point(100.6, 100))) // still < 1 px from anchor
        verify(g.allows(Qt.point(101.2, 100)),  // cumulative > 1 px → accept
               "slow drift should accumulate past the threshold")
    }

    // --- Wheel override ---

    function test_wheelBypassesSentinel() {
        var g = gate()
        g.markWheel()
        verify(g.allows(Qt.point(100, 100)),
               "wheel-active overrides the sentinel rejection")
    }

    function test_wheelBypassesSamePos() {
        var g = gate()
        g.allows(Qt.point(100, 100))
        g.allows(Qt.point(110, 100))
        g.markWheel()
        verify(g.allows(Qt.point(110, 100)),
               "wheel-active overrides the same-position rejection")
    }

    function test_wheelGraceExpires() {
        var g = gate()
        g.markWheel()
        // Past the 500ms wheel-grace window.
        fakeNow += 600
        g.allows(Qt.point(100, 100))      // sentinel (no longer wheel-active)
        verify(!g.allows(Qt.point(100, 100)),
               "after wheel-grace expires the same-pos check engages again")
    }

    function test_wheelGraceWindowCustomizable() {
        var g = gate()
        g.wheelGraceMs = 100
        g.markWheel()
        fakeNow += 50                     // still inside the window
        verify(g.allows(Qt.point(100, 100)))
        g.reset()
        g.markWheel()
        fakeNow += 200                    // past the window
        verify(!g.allows(Qt.point(100, 100)))
    }
}
