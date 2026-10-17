/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for LaunchCoordinator — the single/bulk launch routing extracted
    from GridPanel. Stubs stand in for appsModel / searchModel / plasmoidBridge;
    SignalSpy captures the UI side effects the panel handles (close, the
    calculator substitution paste, the above-threshold bulk-launch confirm).
*/

import QtQuick
import QtTest

import "../../package/contents/ui/controllers"

TestCase {
    id: testCase
    name: "LaunchCoordinator"
    when: windowShown

    property var notified: []
    property var launchedIdx: []
    property var launchedSids: []
    property var hiddenSids: []
    // searchModel.get() result + bridge return values, set per test.
    property var nextItem: null
    property string nextSubst: ""
    property bool nextRunResult: false

    function _reset() {
        notified = []; launchedIdx = []; launchedSids = []; hiddenSids = []
        nextItem = null; nextSubst = ""; nextRunResult = false
        closeSpy.clear(); substSpy.clear(); confirmSpy.clear()
    }

    QtObject {
        id: appsModelStub
        function get(i) { return ({ storageId: "sid-" + i }) }
        function launch(i) { testCase.launchedIdx.push(i) }
        function launchByStorageId(sid) { testCase.launchedSids.push(sid) }
        function hideByStorageId(sid) { testCase.hiddenSids.push(sid) }
    }
    QtObject {
        id: searchModelStub
        function get(i) { return testCase.nextItem }
    }
    QtObject {
        id: bridgeStub
        function notifyAppLaunched(sid) { testCase.notified.push(sid) }
        readonly property var runner: ({
            substitutionText: function(i) { return testCase.nextSubst },
            run: function(i) { return testCase.nextRunResult }
        })
    }

    LaunchCoordinator {
        id: coord
        appsModel: appsModelStub
        searchModel: searchModelStub
        plasmoidBridge: bridgeStub
    }

    SignalSpy { id: closeSpy; target: coord; signalName: "closeRequested" }
    SignalSpy { id: substSpy; target: coord; signalName: "substitutionRequested" }
    SignalSpy { id: confirmSpy; target: coord; signalName: "bulkLaunchConfirmRequested" }

    // launchApp: broadcast the sid, launch by index, request close.
    function test_launchApp() {
        _reset()
        coord.launchApp(3)
        compare(notified.join(","), "sid-3", "notified the storageId")
        compare(launchedIdx.join(","), "3", "launched by index")
        compare(closeSpy.count, 1, "closed once")
    }

    // launchApp guards against a negative index (keyboard Enter with no
    // selection) — no launch, no close.
    function test_launchAppIgnoresNegativeIndex() {
        _reset()
        coord.launchApp(-1)
        compare(notified.length, 0)
        compare(launchedIdx.length, 0)
        compare(closeSpy.count, 0)
    }

    // launchAppByStorageId: broadcast + launch by sid, then close.
    function test_launchAppByStorageId() {
        _reset()
        coord.launchAppByStorageId("alpha")
        compare(notified.join(","), "alpha")
        compare(launchedSids.join(","), "alpha")
        compare(closeSpy.count, 1)
    }

    // A folder's "Launch All" launches each member in place: it must still
    // broadcast the launch, and must not close the launcher per member.
    function test_launchAppByStorageIdNoClose() {
        _reset()
        coord.launchAppByStorageIdNoClose("beta")
        compare(notified.join(","), "beta")
        compare(launchedSids.join(","), "beta")
        compare(closeSpy.count, 0)
        coord.launchAppByStorageIdNoClose("")
        compare(notified.length, 1, "an empty sid is ignored")
    }

    // A search result of type "app" routes to the index launch path.
    function test_launchSearchResultApp() {
        _reset()
        testCase.nextItem = ({ resultType: "app", sourceIndex: 5 })
        coord.launchSearchResult(0)
        compare(launchedIdx.join(","), "5", "launched the app's source index")
        compare(closeSpy.count, 1)
    }

    // A runner result with a substitution (calculator) pastes back into the
    // field via the signal and does NOT close or launch.
    function test_launchSearchResultSubstitution() {
        _reset()
        testCase.nextItem = ({ resultType: "runner", sourceIndex: 2 })
        testCase.nextSubst = "1234"
        coord.launchSearchResult(0)
        compare(substSpy.count, 1, "substitution emitted")
        compare(substSpy.signalArguments[0][0], "1234", "with the substitution text")
        compare(closeSpy.count, 0, "did not close")
        compare(launchedIdx.length, 0)
    }

    // A runner result that runs (no substitution) closes the launcher.
    function test_launchSearchResultRunnerCloses() {
        _reset()
        testCase.nextItem = ({ resultType: "runner", sourceIndex: 2 })
        testCase.nextSubst = ""
        testCase.nextRunResult = true
        coord.launchSearchResult(0)
        compare(closeSpy.count, 1, "closed after the runner ran")
    }

    // Below the confirm threshold (4), requestBulkLaunch fires immediately:
    // one broadcast + one launch per sid, one close.
    function test_requestBulkLaunchBelowThreshold() {
        _reset()
        coord.requestBulkLaunch(["a", "b", "c"])
        compare(notified.join(","), "a,b,c")
        compare(launchedSids.join(","), "a,b,c")
        compare(closeSpy.count, 1, "closed once for the whole batch")
        compare(confirmSpy.count, 0, "no confirm prompt below threshold")
    }

    // At/above the threshold it prompts and launches NOTHING — the guard
    // against opening dozens of apps by accident.
    function test_requestBulkLaunchAboveThresholdPrompts() {
        _reset()
        coord.requestBulkLaunch(["a", "b", "c", "d"]) // 4 == threshold
        compare(confirmSpy.count, 1, "confirm requested")
        compare(launchedSids.length, 0, "nothing launched yet")
        compare(closeSpy.count, 0)
    }

    // runBulkHide hides each sid, no close (hiding keeps the launcher open).
    function test_runBulkHide() {
        _reset()
        coord.runBulkHide(["x", "y"])
        compare(hiddenSids.join(","), "x,y")
        compare(closeSpy.count, 0)
    }
}
