/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for SearchKeyRouter.qml: the search field's keys reach the
    results, the shown grid or the prefix view, and ask for what they cannot
    do themselves.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/controllers"

TestCase {
    id: testCase
    name: "SearchKeyRouter"

    property var calls: []

    QtObject {
        id: resultsStub
        property int currentIndex: 0
        property int count: 3
        function pageUp() { testCase.calls.push("pageUp") }
        function pageDown() { testCase.calls.push("pageDown") }
        function goHome() { testCase.calls.push("home") }
        function goEnd() { testCase.calls.push("end") }
    }
    QtObject {
        id: gridStub
        function enterFromSearch() { testCase.calls.push("enter") }
        function activateCurrent() { testCase.calls.push("activate") }
    }
    QtObject {
        id: filesStub
        function activateFileCurrent() { testCase.calls.push("openFile") }
        function focusFileList() { testCase.calls.push("focusFiles") }
    }

    Component {
        id: routerComponent
        SearchKeyRouter { results: resultsStub; keyView: gridStub; prefixView: filesStub }
    }

    SignalSpy { id: launchSpy; signalName: "launchResultRequested" }
    SignalSpy { id: runSpy; signalName: "runRequested" }
    SignalSpy { id: revealSpy; signalName: "revealRequested" }

    function make(props) {
        calls = []
        resultsStub.currentIndex = 0
        var r = createTemporaryObject(routerComponent, testCase, props || {})
        launchSpy.target = r; runSpy.target = r; revealSpy.target = r
        launchSpy.clear(); runSpy.clear(); revealSpy.clear()
        return r
    }

    function test_resultsTakeTheKeysWhileShown() {
        var r = make({ resultsShown: true, searching: true })
        r.moveDown()
        compare(resultsStub.currentIndex, 1)
        r.moveUp()
        compare(resultsStub.currentIndex, 0)
        r.moveUp()
        compare(resultsStub.currentIndex, 0, "Up stops at the top")
        r.tab(); r.tab(); r.tab()
        compare(resultsStub.currentIndex, 0, "Tab wraps")
        r.accept()
        compare(launchSpy.signalArguments[0][0], 0)
        r.altNumber(3)
        compare(launchSpy.signalArguments[1][0], 2)
        r.altNumber(4)
        compare(launchSpy.count, 2, "no fourth result")
        r.pageDown(); r.home()
        compare(calls.join(","), "pageDown,home")
    }

    function test_theGridTakesTheKeysOtherwise() {
        var r = make()
        r.moveDown()
        r.tab()
        r.accept()
        r.pageDown()
        r.altNumber(1)
        compare(calls.join(","), "enter,enter,activate")
        compare(launchSpy.count, 0)
    }

    function test_prefixModes() {
        var r = make({ prefixMode: "terminal", searching: true })
        r.accept()
        compare(runSpy.signalArguments[0][0], true)
        r.prefixMode = "command"
        r.accept()
        compare(runSpy.signalArguments[1][0], false)
        r.prefixMode = "files"
        r.accept()
        r.moveDown()
        compare(calls.join(","), "openFile,focusFiles")
        r.prefixMode = "help"
        r.accept()
        r.moveDown()
        compare(calls.length, 2, "other prefix views keep their own keys")
    }

    function test_compactGridRevealsAndCollapses() {
        var r = make({ collapsible: true, collapsed: true })
        r.moveDown()
        compare(revealSpy.signalArguments[0][0], true)
        compare(calls.length, 0, "the first Down only reveals")
        r.collapsed = false
        r.revealed = true
        r.moveUp()
        compare(revealSpy.signalArguments[1][0], false)
        r.searching = true
        r.moveUp()
        compare(revealSpy.count, 2, "not while searching")
    }
}
