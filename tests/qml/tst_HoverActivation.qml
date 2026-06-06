/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

TestCase {
    id: tst_HoverActivation
    name: "HoverActivation"

    property var fakeNow: 100000

    function gate(enabled) {
        var c = Qt.createComponent("HoverActivation.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, {
            enabled: enabled === undefined ? true : enabled,
            clock: function() { return tst_HoverActivation.fakeNow }
        })
    }

    // --- Gate ---

    function test_disabledIgnoresEnter() {
        var g = gate(false)
        verify(!g.enter("Games"), "disabled enter should not request a timer")
        compare(g.pending, "", "disabled enter must not arm anything")
    }

    function test_enabledArmsAndRequestsStart() {
        var g = gate(true)
        verify(g.enter("Games"), "enabled enter should request a timer start")
        compare(g.pending, "Games")
    }

    // --- Adjacent switch (enter B before A's leave) ---

    function test_enterRearms() {
        var g = gate(true)
        g.enter("Games")
        verify(g.enter("Office"), "re-entering a new tab should re-request start")
        compare(g.pending, "Office")
    }

    function test_leaveOfStaleTabDoesNotCancel() {
        var g = gate(true)
        g.enter("Office")                 // armed by the just-entered tab
        verify(!g.leave("Games"),         // the previous tab's late leave
               "leave of a tab that is no longer armed must not stop the timer")
        compare(g.pending, "Office", "stale leave must not disarm the new tab")
    }

    // --- Normal leave ---

    function test_leaveOfArmedTabCancels() {
        var g = gate(true)
        g.enter("Games")
        verify(g.leave("Games"), "leaving the armed tab should stop the timer")
        compare(g.pending, "")
    }

    function test_clearDisarms() {
        var g = gate(true)
        g.enter("Games")
        g.clear()
        compare(g.pending, "")
    }

    // --- Suppression grace (wheel scroll or bar entry) ---

    function test_suppressBlocksEnter() {
        var g = gate(true)
        g.suppress()
        verify(!g.enter("Games"), "enter within the grace must be suppressed")
        compare(g.pending, "", "nothing arms during the grace")
    }

    function test_suppressDisarmsPending() {
        var g = gate(true)
        g.enter("Games")
        g.suppress()
        compare(g.pending, "", "suppress drops the in-flight dwell")
    }

    function test_enterResumesAfterGrace() {
        var g = gate(true)
        g.suppress()
        tst_HoverActivation.fakeNow += g.wheelGraceMs + 1
        verify(g.enter("Games"), "after the grace window, hover-select works again")
        compare(g.pending, "Games")
    }
}
