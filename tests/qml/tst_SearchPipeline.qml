/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for SearchPipeline.qml: a burst of keystrokes filters the grid
    once, KRunner gets a fresh query's first character at once and the rest
    after the debounce, and no runner query runs with the extra runners off,
    in a prefix mode, or after the field is cleared.
*/

import QtQuick
import QtTest

TestCase {
    name: "SearchPipeline"

    Component {
        id: viewStateComponent
        QtObject {
            property var applied: []
            function setSearchText(text) { applied.push(text) }
        }
    }
    Component {
        id: runnerComponent
        QtObject { property string queryString: "" }
    }

    function build(props) {
        var c = Qt.createComponent("../../package/contents/ui/controllers/SearchPipeline.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        var p = props || {}
        p.viewState = viewStateComponent.createObject(null)
        p.runnerSourceModel = runnerComponent.createObject(null)
        return c.createObject(null, p)
    }

    function test_burstFiltersTheGridOnce() {
        var s = build()
        s.setText("f")
        s.setText("fi")
        s.setText("fir")
        compare(s.viewState.applied.length, 0)
        tryCompare(s.viewState.applied, "length", 1)
        compare(s.viewState.applied[0], "fir")
    }

    function test_runnerLeadingEdgeThenDebounce() {
        var s = build({ useExtraRunners: true, runnerDebounceMs: 30 })
        s.setText("f")
        compare(s.runnerSourceModel.queryString, "f")
        s.setText("fi")
        compare(s.runnerSourceModel.queryString, "f")
        tryCompare(s.runnerSourceModel, "queryString", "fi")
    }

    function test_noRunnerQueryWithRunnersOff() {
        var s = build({ useExtraRunners: false })
        s.setText("fire")
        wait(60)
        compare(s.runnerSourceModel.queryString, "")
    }

    function test_noRunnerQueryInPrefixMode() {
        var s = build({ useExtraRunners: true, isPrefixMode: true })
        s.setText("t:ls")
        wait(80)
        compare(s.runnerSourceModel.queryString, "")
    }

    function test_clearingStopsThePendingQuery() {
        var s = build({ useExtraRunners: true, runnerDebounceMs: 30 })
        s.setText("f")
        s.setText("fi")
        s.setText("")
        compare(s.runnerSourceModel.queryString, "")
        wait(60)
        compare(s.runnerSourceModel.queryString, "")
    }
}
