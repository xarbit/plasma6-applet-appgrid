/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    PrefixDetector is a thin QML wrapper that binds its `input` through
    prefixmodes.js to the mode / isPrefixMode / argument properties. The
    classification logic itself is covered exhaustively in tst_PrefixModes;
    these tests only prove the wiring — input flows to each derived property.
*/

import QtQuick
import QtTest

TestCase {
    name: "PrefixDetector"

    function detector(input) {
        var c = Qt.createComponent("PrefixDetector.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, { input: input })
    }

    // A prefixed input drives all three derived properties.
    function test_prefixInputBindsModeArgumentAndFlag() {
        var d = detector("t:ls -la")
        compare(d.mode, "terminal")
        compare(d.argument, "ls -la")
        verify(d.isPrefixMode)
        d.destroy()
    }

    // Plain input leaves the detector in the no-mode state.
    function test_plainInputHasNoMode() {
        var d = detector("firefox")
        compare(d.mode, "")
        verify(!d.isPrefixMode)
        d.destroy()
    }

    // The binding is reactive: changing input re-derives the mode.
    function test_inputChangeReclassifies() {
        var d = detector("firefox")
        compare(d.mode, "")
        d.input = "/usr/bin"
        compare(d.mode, "files")
        compare(d.argument, "/usr/bin")
        d.destroy()
    }
}
