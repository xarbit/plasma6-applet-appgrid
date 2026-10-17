/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for CategoryHoverSelect.qml: a dwelled-on tab selects, a wheel
    scroll suppresses that until it settles and then selects the tab under
    the pointer once, and nothing selects while it is off.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/controllers"

TestCase {
    id: testCase
    name: "CategoryHoverSelect"

    property string underPointer: ""

    Component {
        id: selectComponent
        CategoryHoverSelect {
            enabled: true
            tabUnderPointer: () => testCase.underPointer
        }
    }

    SignalSpy { id: selectSpy; signalName: "selectRequested" }

    function make(props) {
        var h = createTemporaryObject(selectComponent, testCase, props || {})
        selectSpy.target = h
        selectSpy.clear()
        underPointer = ""
        return h
    }

    function test_dwellSelects() {
        var h = make()
        h.enter("Games")
        tryCompare(selectSpy, "count", 1)
        compare(selectSpy.signalArguments[0][0], "Games")
    }

    function test_leavingCancelsTheDwell() {
        var h = make()
        h.enter("Games")
        h.leave("Games")
        wait(h.dwell * 4)
        compare(selectSpy.count, 0)
    }

    function test_wheelSettlesOnTheTabUnderThePointer() {
        var h = make()
        h.wheel()
        verify(h.wheelScrolling, "the highlight drops while scrolling")
        h.enter("Office")
        wait(h.dwell * 4)
        compare(selectSpy.count, 0, "no dwell while the wheel scrolls")
        underPointer = "Office"
        tryCompare(h, "wheelScrolling", false, h.wheelGrace * 3)
        compare(selectSpy.count, 1)
        compare(selectSpy.signalArguments[0][0], "Office")
    }

    function test_offSelectsNothing() {
        var h = make({ enabled: false })
        h.enter("Games")
        h.wheel()
        verify(!h.wheelScrolling)
        wait(h.wheelGrace + 50)
        compare(selectSpy.count, 0)
    }
}
