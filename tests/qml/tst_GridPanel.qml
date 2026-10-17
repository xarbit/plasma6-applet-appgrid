/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Integration harness for GridPanel. Proves the inner-widget decoupling:
    GridPanel loads from pure stubs — a QObject configuration, plain-object
    models, and plain-function callbacks — with no live Plasma plasmoid
    context. Asserts default visibility and that the bulk-launch path fires
    the injected launch service once per sid.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "GridPanel"

    // launchService.launch spy.
    property var launchedSids: []

    // Stub configuration — mirrors the ConfigCache `source` surface so
    // GridPanel's single ConfigCache resolves every setting it reads.
    QtObject {
        id: configStub
        property string icon: ""
        property bool useCustomButtonImage: false
        property url customButtonImage: ""
        property string menuLabel: ""
        property bool openOnActiveScreen: false
        property bool showDividers: true
        property bool showScrollbars: true
        property bool independentTextSize: false
        property int verticalOffset: 0
        property bool showTooltips: true
        property bool hoverHighlight: true
        property bool showNewAppBadge: true
        property bool iconShadow: false
        property int iconSize: 64
        property int hoverAnimation: 0
        property bool shakeOnOpen: false
        property int gridColumns: 6
        property int gridRows: 4
        property bool showCategoryBar: false
        property bool hideEmptyCategories: false
        property bool useSystemCategories: false
        property int sortMode: 0
        property bool showRecentApps: false
        property bool hideGridWhenEmpty: false
        property bool startWithFavorites: false
        property bool sortFavoritesAlphabetically: false
        property bool hideLabelsOnFavorites: false
        property var hiddenApps: []
        property var recentApps: []
        property var launchCounts: []
        property bool searchAll: false
        property bool useExtraRunners: false
        property bool searchUsesFrecency: false
        property bool searchShowsHidden: false
        property bool searchInlineCompletion: false
        property bool showSearchShortcuts: false
        property bool hideMenuButtonLabel: false
        property string terminalShell: ""
        property var headerActions: []
        property bool showActionLabels: false
        property bool checkForUpdates: false
    }

    // Stub appsModel — the QML-visible surface of AppFilterModel/AppModel.
    QtObject {
        id: appsModelStub
        property string searchText: ""
        property var recentApps: []
        property var favoriteApps: []
        property var hiddenApps: []
        property var launchCounts: []
        property int maxRecentApps: 6
        property int iconGeneration: 0
        property bool showFavoritesOnly: false
        property bool sortFavoritesAlphabetically: false
        property bool searchShowsHidden: false
        property int sortMode: 0
        property bool useSystemCategories: false
        property string filterCategory: ""
        property string categoryMenuPath: ""

        // Emitted by the production model when the category set changes;
        // CategoryBar connects to it.
        signal categoriesChanged()

        function get(i) { return ({ storageId: "stub-" + i }) }
        function getByStorageId(sid) { return ({ name: "", iconName: "", desktopFile: "", genericName: "", comment: "", installSource: "" }) }
        function categories() { return [] }
        function nonEmptyCategories() { return [] }
        function categoryMenuPath(name) { return "" }
        function isNewApp(sid) { return false }
        function hideApp(i) {}
        function hideByStorageId(sid) {}
        function unhideApp(sid) {}
        function setSearchState(text, category, favoritesOnly) {
            searchText = text
            filterCategory = category
            showFavoritesOnly = favoritesOnly
        }
    }

    QtObject {
        id: searchModelStub
        function get(i) { return ({}) }
    }

    QtObject {
        id: runnerStub
        property string queryString: ""
    }

    function make() {
        var c = Qt.createComponent("../../package/contents/ui/views/GridPanel.qml")
        verify(c.status === Component.Ready, "GridPanel load error: " + c.errorString())
        var bridgeStub = ({
            launchService: ({
                launch: function(sid) { testCase.launchedSids.push(sid); return true },
                launchAction: function(sid, actionName) { return false },
                appActions: function(sid) { return [] }
            }),
            runner: ({
                run: function(idx) { return false },
                runAction: function(idx, actIdx) { return false },
                substitutionText: function(idx) { return "" },
                favoriteId: function(idx) { return "" }
            }),
            systemActions: ({
                runInTerminal: function(cmd, shell) {},
                runCommand: function(cmd, shell) {},
                canManageInDiscover: function(sid) { return false },
                openInDiscover: function(sid) {},
                listDirectory: function(path) { return [] }
            }),
            appsModel: appsModelStub,
            searchModel: searchModelStub,
            runnerSourceModel: runnerStub,
            isUniversalBuild: false
        })
        var obj = c.createObject(null, {
            width: 600,
            height: 800,
            configuration: configStub,
            plasmoidBridge: bridgeStub,
            sysInfoProvider: () => ({})
        })
        verify(obj !== null, "GridPanel create returned null")
        return obj
    }

    // The decoupling milestone: GridPanel constructs with no Plasmoid.
    function test_instantiatesFromStubs() {
        var p = make()
        verify(p, "panel instantiated")
        p.destroy()
    }

    // Bulk launch below the confirm threshold runs immediately, launching
    // through the injected service once per sid.
    function test_bulkLaunchFiresCallbacksPerSid() {
        testCase.launchedSids = []
        var p = make()

        p.launchCoordinator.runBulkLaunch(["alpha", "beta", "gamma"])

        compare(testCase.launchedSids.join(","), "alpha,beta,gamma",
                "launchService.launch fired per sid in order")
        p.destroy()
    }

    // The confirm gate: at/above the threshold (4) _requestBulkLaunch must
    // prompt and launch NOTHING — the guard against opening dozens of apps by
    // accident. This is the riskiest path; without the gate it would fire all.
    function test_bulkLaunchAboveThresholdDoesNotLaunch() {
        testCase.launchedSids = []
        var p = make()

        p.launchCoordinator.requestBulkLaunch(["a", "b", "c", "d"]) // 4 == threshold

        compare(testCase.launchedSids.length, 0, "nothing launched above threshold")
        p.destroy()
    }

    // Below the threshold the same gate fires immediately, no prompt.
    function test_bulkLaunchBelowThresholdFiresImmediately() {
        testCase.launchedSids = []
        var p = make()

        p.launchCoordinator.requestBulkLaunch(["a", "b", "c"]) // 3 < threshold

        compare(testCase.launchedSids.join(","), "a,b,c",
                "launchService.launch fired per sid below threshold")
        p.destroy()
    }

    // The grid and the search list swap only once the model's filter matches
    // the search: switching on the live field text showed the search list
    // with the unfiltered apps for a frame, and on clearing rebuilt the grid
    // from the stale search results before the restored filter landed.
    function test_viewsSwitchAfterFilterApplied() {
        appsModelStub.searchText = ""
        var p = make()
        var bar = findChild(p, "searchBar")
        verify(bar, "search field found")

        // Typing: the filter pass is deferred (Qt.callLater), so right after the
        // keystroke the search list must not show yet with the old query.
        bar.text = "fi"
        verify(!(p.showSearchResults && appsModelStub.searchText !== "fi"),
               "search list shown before the query was applied")
        tryCompare(p, "showSearchResults", true)
        compare(appsModelStub.searchText, "fi")

        // Clearing: the grid must not come back on the stale search filter.
        bar.text = ""
        verify(!(p.showAppGrid && appsModelStub.searchText !== ""),
               "grid shown before the cleared query was applied")
        tryCompare(p, "showAppGrid", true)
        compare(appsModelStub.searchText, "")
        p.destroy()
    }

    // Opening and closing put the panel back to its just-opened state: the
    // search cleared and the views reset, without errors from any of them.
    function test_resetsClearTheSession() {
        var p = make()
        var bar = findChild(p, "searchBar")
        bar.text = "fi"
        p.resetOnClose()
        compare(bar.text, "")
        bar.text = "fi"
        p.resetState()
        compare(bar.text, "")
        p.destroy()
    }

    // Down / Tab / Enter in the search field reach the shown grid through one
    // interface; while searching the results list takes them instead.
    function test_keyViewFollowsTheShownView() {
        appsModelStub.searchText = ""
        var p = make()
        tryCompare(p, "showAppGrid", true)
        verify(p.activeKeyView, "the grid takes the keys")
        compare(typeof p.activeKeyView.enterFromSearch, "function")
        compare(typeof p.activeKeyView.activateCurrent, "function")

        findChild(p, "searchBar").text = "fi"
        tryCompare(p, "showSearchResults", true)
        compare(p.activeKeyView, null, "no grid while searching")
        p.destroy()
    }
}
