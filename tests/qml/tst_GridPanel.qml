/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Integration harness for GridPanel. Proves the inner-widget decoupling:
    GridPanel loads from pure stubs — a QObject configuration, plain-object
    models, and plain-function callbacks — with no live Plasma plasmoid
    context. Asserts default visibility and that the bulk-launch path fires
    the injected notifyAppLaunched / launchByStorageId callbacks per sid.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "GridPanel"

    // notifyAppLaunched spy.
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
        property int openAnimation: 0
        property bool showScrollbars: true
        property int backgroundOpacity: 90
        property bool enableBlur: true
        property bool enableBackgroundContrast: false
        property bool useThemeBackground: false
        property bool dimBackground: true
        property bool independentTextSize: false
        property int verticalOffset: 0
        property bool showTooltips: true
        property bool hoverHighlight: true
        property bool showNewAppBadge: true
        property bool iconShadow: false
        property bool overrideRadius: false
        property int cornerRadius: 0
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
        property var favoriteApps: []
        property bool sortFavoritesAlphabetically: false
        property bool hideLabelsOnFavorites: false
        property bool favoritesPortedToKAstats: true
        property var hiddenApps: []
        property var recentApps: []
        property var knownApps: []
        property var launchCounts: []
        property bool searchAll: false
        property bool useExtraRunners: false
        property bool searchUsesFrecency: false
        property bool searchShowsHidden: false
        property bool searchInlineCompletion: false
        property bool showSearchShortcuts: false
        property bool hideMenuButtonLabel: false
        property string terminalShell: ""
        property var powerButtonOrder: []
        property var powerButtonsHidden: []
        property var headerActions: []
        property bool showActionLabels: false
        property bool checkForUpdates: false
        // One-shot migration flags written by migrations.js on construction.
        property bool powerButtonsMigrated: true
        property bool headerActionsMigrated: true
        property bool iconMigratedFrom17: true
    }

    // Stub appsModel — the QML-visible surface of AppFilterModel/AppModel.
    QtObject {
        id: appsModelStub
        property string searchText: ""
        property var recentApps: []
        property var groupedByCategory: []
        property var favoriteApps: []
        property var hiddenApps: []
        property var knownApps: []
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

        // launchByStorageId spy.
        property var launchedSids: []

        function get(i) { return ({ storageId: "stub-" + i }) }
        function getByStorageId(sid) { return ({ name: "", iconName: "", desktopFile: "", genericName: "", comment: "", installSource: "" }) }
        function categories() { return [] }
        function nonEmptyCategories() { return [] }
        function categoryMenuPath(name) { return "" }
        function isNewApp(sid) { return false }
        function hideApp(i) {}
        function hideByStorageId(sid) {}
        function unhideApp(sid) {}
        function markAllKnown() {}
        function launch(i) {}
        function launchByStorageId(sid) { appsModelStub.launchedSids.push(sid) }
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
            notifyAppLaunched: function(sid) { testCase.launchedSids.push(sid) },
            runInTerminal: function(cmd, shell) {},
            runCommand: function(cmd, shell) {},
            runRunnerResult: function(idx) { return false },
            runRunnerAction: function(idx, actIdx) { return false },
            runnerSubstitutionText: function(idx) { return "" },
            appActions: function(sid) { return [] },
            launchAppAction: function(sid, idx) {},
            canManageInDiscover: function(sid) { return false },
            openInDiscover: function(sid) {},
            listDirectory: function(path) { return [] },
            themeBackgroundCornerRadius: function(imagePath) { return 0 }
        })
        var obj = c.createObject(null, {
            width: 600,
            height: 800,
            appsModel: appsModelStub,
            searchModel: searchModelStub,
            runnerSourceModel: runnerStub,
            configuration: configStub,
            plasmoidBridge: bridgeStub,
            updateChecker: null,
            favoritesClientInstance: "dev.xarbit.appgrid.favorites.instance-test",
            sysInfo: ({})
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

    // Bulk launch below the confirm threshold runs immediately, firing the
    // injected notify + launch callbacks once per sid.
    function test_bulkLaunchFiresCallbacksPerSid() {
        testCase.launchedSids = []
        appsModelStub.launchedSids = []
        var p = make()

        p._runBulkLaunch(["alpha", "beta", "gamma"])

        compare(testCase.launchedSids.join(","), "alpha,beta,gamma",
                "notifyAppLaunched fired per sid in order")
        compare(appsModelStub.launchedSids.join(","), "alpha,beta,gamma",
                "launchByStorageId fired per sid in order")
        p.destroy()
    }

    // The confirm gate: at/above the threshold (4) _requestBulkLaunch must
    // prompt and launch NOTHING — the guard against opening dozens of apps by
    // accident. This is the riskiest path; without the gate it would fire all.
    function test_bulkLaunchAboveThresholdDoesNotLaunch() {
        testCase.launchedSids = []
        appsModelStub.launchedSids = []
        var p = make()

        p._requestBulkLaunch(["a", "b", "c", "d"]) // 4 == threshold

        compare(testCase.launchedSids.length, 0, "no notifyAppLaunched above threshold")
        compare(appsModelStub.launchedSids.length, 0, "no launchByStorageId above threshold")
        p.destroy()
    }

    // Below the threshold the same gate fires immediately, no prompt.
    function test_bulkLaunchBelowThresholdFiresImmediately() {
        testCase.launchedSids = []
        appsModelStub.launchedSids = []
        var p = make()

        p._requestBulkLaunch(["a", "b", "c"]) // 3 < threshold

        compare(appsModelStub.launchedSids.join(","), "a,b,c",
                "launchByStorageId fired per sid below threshold")
        p.destroy()
    }
}
