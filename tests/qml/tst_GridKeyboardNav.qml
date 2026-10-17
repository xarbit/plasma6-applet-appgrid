/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for GridKeyboardNav.qml's arrow handling, shared by both grids:
    the cursor it asks for, leaving for the search field, Alt paging and
    Shift extending the selection.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/controllers"

TestCase {
    id: testCase
    name: "GridKeyboardNav"

    property var extended: []

    QtObject {
        id: selectionStub
        property int virtualIndex: 0
        function extendOrMove(event, moveFn, indexFn) {
            moveFn()
            testCase.extended.push(indexFn())
        }
    }

    Component {
        id: navComponent
        GridKeyboardNav {
            recentCount: 0
            gridCount: 10
            columns: 4
            selection: selectionStub
        }
    }

    SignalSpy { id: cursorSpy; signalName: "cursorRequested" }
    SignalSpy { id: exitSpy; signalName: "exitRequested" }
    SignalSpy { id: pageSpy; signalName: "categoryNavRequested" }

    function make(props) {
        var nav = createTemporaryObject(navComponent, testCase, props || {})
        cursorSpy.target = nav; exitSpy.target = nav; pageSpy.target = nav
        cursorSpy.clear(); exitSpy.clear(); pageSpy.clear()
        extended = []
        return nav
    }
    function key(k, modifiers) { return ({ key: k, modifiers: modifiers || 0, accepted: false }) }

    function test_arrowsMoveTheCursor() {
        var nav = make({ gridIndex: 5 })
        var e = key(Qt.Key_Down)
        nav.handleArrow(e)
        verify(e.accepted)
        compare(cursorSpy.signalArguments[0][0], -1)
        compare(cursorSpy.signalArguments[0][1], 9)
    }

    function test_upFromTheTopRowLeaves() {
        var nav = make({ gridIndex: 2 })
        nav.handleArrow(key(Qt.Key_Up))
        compare(exitSpy.count, 1)
        compare(cursorSpy.count, 0)
    }

    function test_altPagesTheCategories() {
        var nav = make({ gridIndex: 2 })
        nav.handleArrow(key(Qt.Key_Right, Qt.AltModifier))
        compare(pageSpy.signalArguments[0][0], 1)
        compare(cursorSpy.count, 0)
    }

    function test_selectionExtendsOnlyWhenActive() {
        var nav = make({ gridIndex: 2 })
        nav.handleArrow(key(Qt.Key_Right, Qt.ShiftModifier))
        compare(extended.length, 0, "multi-selection off: a plain move")
        compare(cursorSpy.count, 1)
        nav.selectionActive = true
        nav.handleArrow(key(Qt.Key_Right, Qt.ShiftModifier))
        compare(extended.length, 1, "through the selection")
        compare(cursorSpy.count, 2)
        nav.gridIndex = -1
        nav.handleArrow(key(Qt.Key_Down, Qt.ShiftModifier))
        compare(extended.length, 1, "the first landing doesn't extend")
    }
}
