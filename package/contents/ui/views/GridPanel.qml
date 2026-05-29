/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable grid panel content. Used by GridWindow (Center variant — opens
    centered over a dim overlay) and as a native Plasma popup (Panel variant
    — opens near the panel icon).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../widgets"
import "../js/migrations.js" as Migrations
import "../js/searchresultnav.js" as SearchResultNav

Kirigami.ShadowedRectangle {
    id: panel

    signal closeRequested()
    // Plasmoid root. Deliberately `var`, not typed as PlasmoidItem,
    // for two reasons: typing it would force every consumer to import
    // `org.kde.plasma.plasmoid`, and keeping the contract structural lets
    // tests pass plain QtObject mocks that expose the same properties
    // (dragSource, isDragInFlight, closeWindow(), favoritesDragProxy, …).
    property var appletInterface: null

    function shakeAllIcons() {
        appGrid.shakeAllIcons()
        categoryGridView.shakeAllIcons()
    }

    // C++ models supplied by the owning plasmoid root. Injected here
    // rather than reached through Plasmoid.* so the panel doesn't grab
    // its dependencies from a global and so tests can pass stubs.
    required property var appsModel
    required property var searchModel
    required property var runnerSourceModel

    // Read-write handle to Plasmoid.configuration. Reads route through
    // ConfigCache (`cfg`) below; writes still target this handle directly
    // for the launch-bookkeeping flush (recents / launchCounts / knownApps /
    // hiddenApps / favoritesPortedToKAstats / iconMigratedFrom17).
    required property var configuration

    // Side-effect callbacks supplied by the plasmoid root. notifyAppLaunched
    // broadcasts an app launch to KActivities (one-way courtesy ping for
    // other Plasma launchers); runInTerminal / runCommand execute the
    // prefix-mode `t:` and `:` shell hooks; runRunnerResult triggers a
    // KRunner result by index. Injected so tests can capture call
    // arguments without spawning real processes.
    required property var notifyAppLaunched
    required property var runInTerminal
    required property var runCommand
    required property var runRunnerResult

    // Update-checker handle (null on distro packages); forwarded to HeaderActionStrip.
    required property var updateChecker

    // KAStats favorites client id, built from the plasmoid id at the root.
    required property string favoritesClientInstance

    // Plasmoid C++ invokables, forwarded to AppContextMenu.
    required property var appActions
    required property var launchAppAction
    required property var canManageInDiscover
    required property var openInDiscover

    // Plasmoid C++ invokables/snapshots, forwarded to the prefix views.
    required property var listDirectory
    required property var sysInfo

    // -- Configuration (single source of truth for all config reads) --
    ConfigCache { id: cfg; source: panel.configuration }
    readonly property alias columns: cfg.gridColumns
    readonly property alias rows: cfg.gridRows
    readonly property alias sortMode: cfg.sortMode
    readonly property alias cfgShowCategoryBar: cfg.showCategoryBar
    readonly property alias cfgStartWithFavorites: cfg.startWithFavorites
    readonly property alias cfgShowRecentApps: cfg.showRecentApps
    readonly property alias cfgShowDividers: cfg.showDividers
    readonly property alias cfgShowTooltips: cfg.showTooltips
    readonly property alias cfgShowNewAppBadge: cfg.showNewAppBadge
    readonly property alias cfgHideLabelsOnFavorites: cfg.hideLabelsOnFavorites
    readonly property alias cfgUseExtraRunners: cfg.useExtraRunners
    readonly property alias cfgHideGridWhenEmpty: cfg.hideGridWhenEmpty

    // -- Sort helpers --
    readonly property bool isSortByCategory: sortMode === 2

    // -- View state --
    // hideGridWhenEmpty: Compact mode — suppress grid/category chrome
    // until the user types. Search and prefix views still take over once
    // the user starts entering text. _gridRevealed lets the user pop the
    // grid open manually (Down arrow from the search bar) without typing.
    // The five visibility outputs and the _gridRevealed flag all live on
    // visibility (VisibilityState.qml); the aliases below preserve the
    // existing call sites.
    readonly property bool isSearching: searchBar.text.length > 0
    readonly property bool isFavoritesActive: categoryBar.favoritesActive

    VisibilityState {
        id: visibility
        nativePopup: panel.nativePopup
        hideGridWhenEmpty: panel.cfgHideGridWhenEmpty
        showCategoryBar: panel.cfgShowCategoryBar
        isSearching: panel.isSearching
        isPrefixMode: panel.isPrefixMode
        isFavoritesActive: panel.isFavoritesActive
        isSortByCategory: panel.isSortByCategory
    }

    property alias _gridRevealed: visibility.gridRevealed
    readonly property alias _emptyHiddenState: visibility.emptyHidden
    readonly property alias showCatBar: visibility.catBarVisible
    readonly property alias showCategoryGrid: visibility.categoryGridVisible
    readonly property alias showAppGrid: visibility.appGridVisible
    readonly property alias showSearchResults: visibility.searchResultsVisible

    readonly property string currentResultIcon: {
        if (!showSearchResults || !panel.searchModel || searchResultsList.count <= 0)
            return ""
        const idx = searchResultsList.currentIndex >= 0 ? searchResultsList.currentIndex : 0
        const item = panel.searchModel.get(idx)
        return item ? (item.iconName || "application-x-executable") : ""
    }

    // Whichever grid view currently owns a SelectionState — used to route
    // menu-driven selection toggles. Search and prefix views resolve to
    // null because they don't host multi-select; callers treat that as a
    // silent no-op.
    readonly property var activeMultiSelectView: showAppGrid ? appGrid
                                              : showCategoryGrid ? categoryGridView
                                              : null

    // -- Icon size mapping (0=Small/medium, 1=Medium/large, 2=Large/huge) --
    readonly property real gridIconSize: {
        var preset = cfg.iconSize
        if (preset === 0) return Kirigami.Units.iconSizes.medium
        if (preset === 1) return Kirigami.Units.iconSizes.large
        return Kirigami.Units.iconSizes.huge
    }

    // -- Prefix mode detection --
    PrefixDetector { id: prefixDetector; input: searchBar.text }
    readonly property string prefixMode: prefixDetector.mode
    readonly property bool isPrefixMode: prefixDetector.isPrefixMode
    readonly property string prefixArgument: prefixDetector.argument

    property bool _needsScrollToTop: false

    // When used as a native Plasma popup, skip custom chrome (Plasma provides its own)
    property bool nativePopup: false

    // Icon-based estimate avoids the circular dependency panel width →
    // grid cellWidth → grid width → panel width. estCellHeight must match
    // AppGridView.cellHeight with labels visible (gridUnit too small per
    // row would accumulate and clip the bottom row).
    readonly property real estCellWidth: gridIconSize + Kirigami.Units.gridUnit * 2
                                         + Kirigami.Units.smallSpacing * 2
    readonly property real estCellHeight: gridIconSize + Kirigami.Units.gridUnit * 3
                                          + Kirigami.Units.smallSpacing * 2

    readonly property real panelMargin: nativePopup ? Kirigami.Units.largeSpacing : Kirigami.Units.largeSpacing * 2
    readonly property real headerHeight: Kirigami.Units.gridUnit * 5
    readonly property real panelWidth: estCellWidth * columns + panelMargin * 2
    readonly property real panelHeight: estCellHeight * rows + panelMargin * 2 + headerHeight
    // Compact mode height — snug fit around the header row (search +
    // power buttons), no slack for a category bar or grid below.
    readonly property real compactHeight: headerRow.implicitHeight + panelMargin * 2
    readonly property real effectiveHeight: _emptyHiddenState ? compactHeight : panelHeight
    // Negative half-delta between the current and full height. With this
    // offset the expanded panel sits at the standard centered position
    // (shift = 0); the compact panel slides up to where the full panel
    // would put its search bar, so the visible search results stay
    // vertically centered when the user starts typing. Consumed by
    // GridWindow for the panel translate and the blur clip; zero when
    // compact mode is off.
    readonly property real compactShift: cfgHideGridWhenEmpty
        ? (height - panelHeight) / 2
        : 0

    // Center variant: GridWindow centers a fixed-size panel, so the size
    // is hard-bound to the icon-grid estimate (compact-mode aware).
    // Panel variant: only seed the *initial* popup size via implicitWidth/
    // Height and leave width/height + preferred size unbound, so Plasma's
    // own popup-resize persistence owns it. A hard preferred-size binding
    // re-asserted the estimate on every layout pass (e.g. a monitor wake)
    // and snapped the user's edge-drag back, shrinking the popup (#146).
    implicitWidth: nativePopup ? panelWidth : 0
    implicitHeight: nativePopup ? panelHeight : 0

    Binding on width {
        when: !panel.nativePopup
        value: Math.min(panel.panelWidth, Screen.width * 0.9)
    }
    Binding on height {
        when: !panel.nativePopup
        value: Math.min(panel.effectiveHeight, Screen.height * 0.9)
    }

    // Set by on_EmptyHiddenStateChanged to skip the next height Behavior
    // animation. See the comment on that handler for the full rationale.
    property bool _snapHeight: false

    Behavior on height {
        enabled: !panel.nativePopup && cfgHideGridWhenEmpty && !panel._snapHeight
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
    }

    Layout.preferredWidth: nativePopup ? -1 : width
    Layout.preferredHeight: nativePopup ? -1 : height
    Layout.minimumWidth: nativePopup ? Kirigami.Units.gridUnit * 12 : width
    Layout.minimumHeight: nativePopup ? Kirigami.Units.gridUnit * 12 : height
    radius: nativePopup ? 0
            : (cfg.overrideRadius ? cfg.cornerRadius : Kirigami.Units.cornerRadius)

    readonly property real bgOpacity: cfg.backgroundOpacity / 100
    color: nativePopup ? "transparent"
           : Qt.rgba(Kirigami.Theme.backgroundColor.r,
                     Kirigami.Theme.backgroundColor.g,
                     Kirigami.Theme.backgroundColor.b,
                     bgOpacity)

    border.width: nativePopup ? 0 : 1
    border.color: nativePopup ? "transparent"
                  : Kirigami.ColorUtils.linearInterpolation(
                        Kirigami.Theme.backgroundColor,
                        Kirigami.Theme.textColor, 0.2)

    shadow.size: nativePopup ? 0 : Kirigami.Units.gridUnit
    shadow.color: nativePopup ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
    shadow.xOffset: 0
    shadow.yOffset: nativePopup ? 0 : Kirigami.Units.smallSpacing

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    // Compact mode: wheel toggles the grid while the search field has
    // focus and there's no active query — down reveals, up collapses,
    // mirroring the Down/Up-arrow behavior. Once typing starts, wheel
    // events fall through so the search results list can scroll.
    WheelHandler {
        enabled: panel.cfgHideGridWhenEmpty && !panel.isSearching
                 && searchBar.field.activeFocus
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            panel._gridRevealed = event.angleDelta.y < 0
            event.accepted = true
        }
    }

    // -- Launch counts serialization helpers --
    function launchCountsToMap(list) {
        var map = {}
        if (list) {
            for (var i = 0; i < list.length; i++) {
                var parts = list[i].split("=")
                if (parts.length === 2)
                    map[parts[0]] = parseInt(parts[1]) || 0
            }
        }
        return map
    }

    function launchCountsToList(map) {
        var list = []
        for (var key in map)
            if (map[key] > 0)
                list.push(key + "=" + map[key])
        return list
    }

    // Sync model properties from config — called on init and reset
    function syncModelFromConfig() {
        if (!appsModel) return
        appsModel.hiddenApps = cfg.hiddenApps
        // Favorites are loaded from KAStatsFavoritesModel after migration —
        // see FavoritesManager.qml.
        appsModel.maxRecentApps = columns
        appsModel.sortMode = sortMode
        appsModel.useSystemCategories = cfg.useSystemCategories
        appsModel.sortFavoritesAlphabetically = cfg.sortFavoritesAlphabetically
        appsModel.launchCounts = launchCountsToMap(cfg.launchCounts)
        appsModel.knownApps = cfg.knownApps
        appsModel.recentApps = cfgShowRecentApps ? cfg.recentApps : []
        if (appsModel.knownApps.length === 0)
            appsModel.markAllKnown()
    }

    Component.onCompleted: {
        Migrations.migratePowerButtons(panel.configuration)
        Migrations.migrateHeaderActions(panel.configuration)
        syncModelFromConfig()
    }
    onColumnsChanged: if (appsModel) appsModel.maxRecentApps = columns

    Connections {
        target: panel.appsModel
        function onRecentAppsChanged() {
            panel.configuration.recentApps = panel.appsModel.recentApps
        }
        function onLaunchCountsChanged() {
            panel.configuration.launchCounts = panel.launchCountsToList(panel.appsModel.launchCounts)
        }
        function onKnownAppsChanged() {
            panel.configuration.knownApps = panel.appsModel.knownApps
        }
    }

    // -- KActivities-backed favorites (always the source of truth) --
    FavoritesManager {
        id: favorites
        appsModel: panel.appsModel
        clientInstance: panel.favoritesClientInstance
        sortFavoritesAlphabetically: cfg.sortFavoritesAlphabetically
        favoritesPortedToKAstats: cfg.favoritesPortedToKAstats
        legacyFavorites: cfg.favoriteApps
        markPorted: function() { panel.configuration.favoritesPortedToKAstats = true }
    }
    readonly property alias favoriteIdRole: favorites.favoriteIdRole
    readonly property alias sharedFavoritesModel: favorites.sharedFavoritesModel
    readonly property alias mirrorRequired: favorites.mirrorRequired


    // Snap the panel height instantly on every compact-mode transition
    // (open/close, typing into the search bar, revealing the grid) so
    // children don't reflow inside an animating panel and the blur clip
    // doesn't chase a shrinking surface during a close fade-out.
    on_EmptyHiddenStateChanged: {
        _snapHeight = true
        Qt.callLater(function() { _snapHeight = false })
    }

    // Reset everything that should be back to its just-opened state on
    // every show or hide: the search input (SearchBar.onTextChanged
    // propagates the empty string into appsModel and runnerSourceModel)
    // and the compact-mode reveal flag.
    function _resetSearchSession() {
        searchBar.text = ""
        _gridRevealed = false
    }

    // Done on close (not open) so the height/scroll transitions back to
    // the compact-mode starting state are invisible behind the fade-out
    // instead of flashing on the next open.
    function resetOnClose() {
        categoryBar.resetScroll()
        _resetSearchSession()
    }

    // -- Reset state (called when showing the grid) --
    function resetState() {
        contextMenu.close()
        categoryBar.closeCategoryMenu()
        headerActionStrip.closeMenus()
        _resetSearchSession()

        // Restore starting tab
        var startFav = cfgShowCategoryBar && cfgStartWithFavorites
        categoryBar.favoritesActive = startFav
        categoryBar.scrollOnlySelected = ""

        // Sync model from config and reset filter state
        syncModelFromConfig()
        if (appsModel) {
            appsModel.searchText = ""
            appsModel.filterCategory = ""
            appsModel.showFavoritesOnly = startFav
        }

        // Reset grid state
        appGrid.clearShuffles()
        appGrid.clearSelection()
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        searchResultsList.currentIndex = 0
        categoryGridView.contentY = 0
        categoryGridView.clearSelection()
        categoryGridView.currentIndex = -1
        categoryGridView.recentIndex = -1
        _needsScrollToTop = true
        searchBar.field.forceActiveFocus()
    }

    function launchSearchResult(index) {
        var item = panel.searchModel.get(index)
        if (!item) return
        if (item.resultType === "app") {
            launchApp(item.sourceIndex)
        } else {
            if (panel.runRunnerResult(item.sourceIndex))
                closeRequested()
        }
    }

    // One launch step: KActivities broadcast plus the model launch. Shared
    // by the single-sid path and the bulk path so neither has to repeat
    // the notify/launch pair (notifyAppLaunched is the one-way broadcast
    // that lets other Plasma launchers count AppGrid as a contributing
    // source — we don't read this data back).
    function _launchOneBySid(sid) {
        if (!sid) return
        notifyAppLaunched(sid)
        appsModel.launchByStorageId(sid)
    }

    function launchApp(index) {
        if (!appsModel || index < 0)
            return
        const sid = appsModel.get(index).storageId
        if (sid) notifyAppLaunched(sid)
        appsModel.launch(index)
        closeRequested()
    }

    function launchAppByStorageId(sid) {
        if (!appsModel || !sid)
            return
        _launchOneBySid(sid)
        closeRequested()
    }

    // Eat clicks so they don't pass through the panel
    MouseArea { anchors.fill: parent }

    // Page the category bar by direction (-1 / +1) when it is visible —
    // the single entry point for panel Alt+Left/Right and the grid's
    // categoryNavRequested signal.
    function navigateCategory(direction) {
        if (categoryBar.visible)
            categoryBar.selectAdjacentCategory(direction)
    }

    // Category bar keyboard navigation: Alt+letter mnemonics, Alt+Left/Right.
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Alt)
            categoryBar.altHeld = true
        if (!categoryBar.visible || !(event.modifiers & Qt.AltModifier))
            return
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            if (categoryBar.selectByMnemonic(event.key))
                event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            navigateCategory(event.key === Qt.Key_Right ? 1 : -1)
            event.accepted = true
        }
    }
    Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Alt)
            categoryBar.altHeld = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: panel.panelMargin
        spacing: Kirigami.Units.largeSpacing

        // -- Header --
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            // Pin the row height so it does not shrink when the power
            // buttons hide on search — implicitHeight ignores hidden
            // children, so derive it from both regardless of visibility.
            Layout.preferredHeight: Math.max(searchBar.implicitHeight,
                                             headerActionStrip.implicitHeight)

            SearchBar {
                id: searchBar

                SearchSessionManager {
                    id: searchSession
                    appsModel: panel.appsModel
                    categoryBar: categoryBar
                    searchAll: cfg.searchAll
                    isPrefixMode: panel.isPrefixMode
                }

                // Debounce KRunner queries — fires after typing pauses
                Timer {
                    id: runnerDebounce
                    interval: 100
                    onTriggered: {
                        if (panel.runnerSourceModel) {
                            var q = searchBar.text
                            var searching = q.length > 0 && !panel.isPrefixMode
                                            && panel.cfgUseExtraRunners
                            panel.runnerSourceModel.queryString = searching ? q : ""
                        }
                    }
                }

                onTextChanged: {
                    searchSession.update(text)
                    var searching = text.length > 0 && !panel.isPrefixMode

                    // KRunner query is debounced (expensive D-Bus calls), and
                    // only runs when the user opted into extra runners.
                    if (searching && panel.cfgUseExtraRunners)
                        runnerDebounce.restart()
                    else if (panel.runnerSourceModel)
                        panel.runnerSourceModel.queryString = ""
                }
                onAltLetterPressed: function(key) {
                    if (categoryBar.visible)
                        categoryBar.selectByMnemonic(key)
                }
            onAltNumberPressed: function(number) {
                    if (!panel.isSearching || panel.isPrefixMode) return
                    if (number >= 1 && number <= searchResultsList.count)
                        panel.launchSearchResult(number - 1)
                }
                onAccepted: {
                    if (panel.prefixMode === "terminal") {
                        panel.runInTerminal(panel.prefixArgument, cfg.terminalShell)
                        panel.closeRequested()
                    } else if (panel.prefixMode === "command") {
                        panel.runCommand(panel.prefixArgument, cfg.terminalShell)
                        panel.closeRequested()
                    } else if (panel.prefixMode === "files") {
                        prefixModeView.activateFileCurrent()
                    } else if (!panel.isPrefixMode) {
                        if (panel.isSearching) {
                            var idx = searchResultsList.currentIndex >= 0 ? searchResultsList.currentIndex : 0
                            if (searchResultsList.count > 0) panel.launchSearchResult(idx)
                        } else {
                            // SearchBar holds focus by default, so Enter has
                            // to delegate to whichever grid currently owns
                            // the keyboard contract (and the selection).
                            const v = panel.activeMultiSelectView
                            if (v) v.activateCurrent()
                            else if (appGrid.currentIndex >= 0)
                                panel.launchApp(appGrid.currentIndex)
                        }
                    }
                }
                readonly property int resultNavPrevious: -1
                readonly property int resultNavNext: 1
                function navigateToResults(step, wrap) {
                    if (panel.isSearching && !panel.isPrefixMode) {
                        const next = SearchResultNav.nextIndex(
                            searchResultsList.currentIndex,
                            searchResultsList.count,
                            step,
                            wrap === true)
                        if (next !== searchResultsList.currentIndex)
                            searchResultsList.currentIndex = next
                    } else if (panel.showCategoryGrid) {
                        categoryGridView.forceActiveFocus()
                        if (categoryGridView.currentIndex < 0) {
                            categoryGridView.contentY = 0
                            categoryGridView.selectFirst()
                        } else {
                            categoryGridView.ensureVisible()
                        }
                    } else if (!panel.isSearching) {
                        appGrid.forceActiveFocus()
                        if (appGrid.showRecents) {
                            appGrid.recentIndex = 0
                            appGrid.currentIndex = -1
                        } else {
                            appGrid.currentIndex = 0
                        }
                    }
                }

                onMoveDown: {
                    if (panel.prefixMode === "files") {
                        prefixModeView.focusFileList()
                        return
                    }
                    // Compact mode: first Down reveals the grid and
                    // keeps focus in the search bar; the next Down then
                    // takes the normal navigateToResults path.
                    if (panel._emptyHiddenState) {
                        panel._gridRevealed = true
                        return
                    }
                    navigateToResults(resultNavNext)
                }
                onMoveUp: {
                    if (panel.isSearching && !panel.isPrefixMode) {
                        navigateToResults(resultNavPrevious)
                        return
                    }
                    if (panel.cfgHideGridWhenEmpty && panel._gridRevealed
                        && !panel.isSearching)
                        panel._gridRevealed = false
                }
                onTabPressed: navigateToResults(resultNavNext, true)
                onPageUp: if (panel.showSearchResults) searchResultsList.pageUp()
                onPageDown: if (panel.showSearchResults) searchResultsList.pageDown()
                onHome: if (panel.showSearchResults) searchResultsList.goHome()
                onEnd: if (panel.showSearchResults) searchResultsList.goEnd()
            }

            HeaderActionStrip {
                id: headerActionStrip
                visible: !panel.isSearching
                showActionLabels: cfg.showActionLabels
                headerActions: cfg.headerActions
                updateChecker: panel.updateChecker
                onActionTriggered: panel.closeRequested()
            }

            // Current search-result icon, shown in place of the power
            // buttons while searching. Fixed size — a fillHeight icon rounds
            // to different standard sizes as the header reflows, making it
            // visibly jump.
            ShadowedIcon {
                visible: panel.showSearchResults && panel.currentResultIcon !== ""
                source: panel.currentResultIcon
                shadowEnabled: cfg.iconShadow
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
        }

        // -- Category bar --
        Kirigami.Separator {
            Layout.fillWidth: true
            visible: panel.showCatBar
            opacity: panel.cfgShowDividers ? 1 : 0
        }

        CategoryBar {
            id: categoryBar
            visible: panel.showCatBar
            Layout.leftMargin: Kirigami.Units.smallSpacing
            appsModel: panel.appsModel
            favoritesFirst: panel.cfgStartWithFavorites
            isSortByCategory: panel.isSortByCategory
            scrollOnlyMode: panel.showCategoryGrid
            hideEmptyCategories: cfg.hideEmptyCategories
            onFavoritesToggled: function(active) {
                // Update model state BEFORE UI state so bindings see the
                // correct proxy data when showCategoryGrid re-evaluates.
                if (panel.appsModel) {
                    panel.appsModel.showFavoritesOnly = active
                    panel.appsModel.filterCategory = ""
                }
                categoryBar.favoritesActive = active
                if (!active) {
                    if (panel.isSortByCategory) {
                        categoryBar.scrollOnlySelected = ""
                        categoryGridView.contentY = 0
        categoryGridView.currentIndex = -1
        categoryGridView.recentIndex = -1
                    }
                }
                searchBar.field.forceActiveFocus()
            }
            onCategorySelected: function(name) {
                searchBar.field.forceActiveFocus()
                if (panel.isSortByCategory) {
                    if (name !== "") {
                        Qt.callLater(function() {
                            categoryGridView.scrollToCategory(name)
                        })
                    } else {
                        categoryGridView.contentY = 0
        categoryGridView.currentIndex = -1
        categoryGridView.recentIndex = -1
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
            visible: panel.showCatBar
            opacity: panel.cfgShowDividers ? 1 : 0
        }

        // -- Prefix mode view --
        PrefixModeView {
            id: prefixModeView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.isPrefixMode
            mode: panel.prefixMode
            argument: panel.prefixArgument
            searchField: searchBar.field
            sharedFavoritesModel: panel.sharedFavoritesModel
            showScrollbars: cfg.showScrollbars
            appsModel: panel.appsModel
            setHiddenApps: function(list) { panel.configuration.hiddenApps = list }
            listDirectory: panel.listDirectory
            sysInfo: panel.sysInfo
            updateChecker: panel.updateChecker
            favoritesPortedToKAstats: cfg.favoritesPortedToKAstats
            favoriteApps: cfg.favoriteApps
            markUnported: function() { panel.configuration.favoritesPortedToKAstats = false }
            onFileOpened: panel.closeRequested()
            onDirectoryNavigated: function(path) {
                searchBar.text = path
            }
        }

        // -- Unified search results --
        SearchResultsList {
            id: searchResultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.showSearchResults
            PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
            model: panel.isSearching ? panel.searchModel : null
            iconSize: panel.gridIconSize
            showDividers: panel.cfgShowDividers
            shadowEnabled: cfg.iconShadow
            animateHighlight: cfg.hoverAnimation > 0
            searchField: searchBar.field
            onLaunched: function(index) { panel.launchSearchResult(index) }
            onContextMenuRequested: function(index, storageId, desktopFile) {
                if (storageId)
                    contextMenu.showForApp(-1, storageId, desktopFile)
            }
        }

        // -- Category grid (By Category sort) --
        CategoryGridView {
            id: categoryGridView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.showCategoryGrid
            PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
            searchField: searchBar.field
            appsModel: panel.appsModel
            groupedApps: panel.showCategoryGrid && panel.appsModel
                ? panel.appsModel.groupedByCategory : []
            cellWidth: Math.floor(categoryGridView.width / panel.columns)
            cellHeight: panel.gridIconSize
                        + Kirigami.Units.gridUnit * 3
                        + Kirigami.Units.smallSpacing * 2
            iconSize: panel.gridIconSize
            hoverAnimation: cfg.hoverAnimation
            shadowEnabled: cfg.iconShadow
            showDividers: panel.cfgShowDividers
            showTooltips: panel.cfgShowTooltips
            showNewAppBadge: panel.cfgShowNewAppBadge
            dragSource: panel.appletInterface
                                ? panel.appletInterface.dragSource : null
            showRecents: panel.cfgShowRecentApps
                         && panel.appsModel
                         && panel.appsModel.recentApps.length > 0
                         && !panel.isFavoritesActive
                         && !panel.cfgStartWithFavorites
            onLaunched: function(proxyIndex) { panel.launchApp(proxyIndex) }
            onRecentLaunched: function(storageId) { panel.launchAppByStorageId(storageId) }
            onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
            onContextMenuRequested: function(proxyIndex, storageId, desktopFile) {
                contextMenu.showForApp(proxyIndex, storageId, desktopFile,
                                       categoryGridView.selectedSidList())
            }
        }

        // -- App grid --
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.showAppGrid

            AppGridView {
                id: appGrid
                anchors.fill: parent
                PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
                // In favorites tab, drive the grid from KAStats directly so
                // reorder animations and pointer grabs work natively.
                // Elsewhere, or when alphabetical sort is enabled (which
                // KAStats does not support), use the filter proxy.
                model: panel.isSearching ? null
                       : (panel.isFavoritesActive
                          && panel.sharedFavoritesModel
                          && !cfg.sortFavoritesAlphabetically
                          ? panel.sharedFavoritesModel
                          : panel.appsModel)
                appsModel: panel.appsModel
                sharedFavoritesModel: panel.sharedFavoritesModel
                favoriteIdRole: panel.favoriteIdRole
                dragSource: panel.appletInterface
                                    ? panel.appletInterface.dragSource : null
                columns: panel.columns
                adaptiveColumns: panel.nativePopup
                iconSize: panel.gridIconSize
                hoverAnimation: cfg.hoverAnimation
                shadowEnabled: cfg.iconShadow
                sortFavoritesAlphabetically: cfg.sortFavoritesAlphabetically
                searchField: searchBar.field
                showRecentApps: panel.cfgShowRecentApps
                startWithFavorites: panel.cfgStartWithFavorites
                favoritesActive: panel.isFavoritesActive
                showDividers: panel.cfgShowDividers
                showTooltips: panel.cfgShowTooltips
                showNewAppBadge: panel.cfgShowNewAppBadge
                hideLabelsOnFavorites: panel.cfgHideLabelsOnFavorites
                animateHighlight: cfg.hoverAnimation > 0
                shuffleOverlayParent: shuffleOverlay
                onOriginYChanged: {
                    if (panel._needsScrollToTop) {
                        contentY = originY
                        panel._needsScrollToTop = false
                    }
                }
                onLaunched: function(index) { panel.launchApp(index) }
                onCategoryNavRequested: function(direction) { panel.navigateCategory(direction) }
                onRecentLaunched: function(storageId) { panel.launchAppByStorageId(storageId) }
                onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
                onContextMenuRequested: function(index, storageId, desktopFile) {
                    // Forward the full live selection — the menu derives
                    // both popupIsSelected (for the toggle item) and the
                    // bulk-mode counts from it. Empty when nothing is
                    // selected.
                    contextMenu.showForApp(index, storageId, desktopFile,
                                           appGrid.selectedSidList())
                }
                onShuffleAnimRequested: function(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex) {
                    shuffleOverlay.startAnim(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex)
                }
            }

            ShuffleOverlay {
                id: shuffleOverlay
                anchors.fill: parent
                z: 10
                iconSize: panel.gridIconSize
                onSwapFinished: function(fromIndex, toIndex, fromIcon, toIcon) {
                    appGrid.applySwap(fromIndex, toIndex, fromIcon, toIcon)
                }
            }

        }
    }


    // -----------------------------------------------------------------------
    // Context menu
    // -----------------------------------------------------------------------

    AppContextMenu {
        id: contextMenu
        appsModel: panel.appsModel
        sharedFavoritesModel: panel.sharedFavoritesModel
        appletInterface: panel.appletInterface

        appActions: panel.appActions
        launchAppAction: panel.launchAppAction
        canManageInDiscover: panel.canManageInDiscover
        openInDiscover: panel.openInDiscover
        setHiddenApps: function(list) { panel.configuration.hiddenApps = list }

        onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
        onBulkHideRequested: function(sids) {
            if (!sids || sids.length === 0) return
            bulkHideDialog.pendingSids = sids
            bulkHideDialog.open()
        }

        // Route the menu's "Add / Remove from Selection" item to whichever
        // grid currently owns the selection state. Resolved via the
        // panel.activeMultiSelectView binding — search results and recents
        // resolve to null, so the toggle silently no-ops there.
        onToggleSelectionRequested: function(sid) {
            const v = panel.activeMultiSelectView
            if (v && sid) v.toggleSelectionBySid(sid)
        }
    }

    // Direct fire below the threshold (typical workflow bundles are
    // 2-3 apps); above it we prompt because launching e.g. all 80
    // installed apps would be an irrecoverable surprise.
    readonly property int _bulkLaunchConfirmThreshold: 4

    function _requestBulkLaunch(sids) {
        if (!sids || sids.length === 0) return
        if (sids.length >= _bulkLaunchConfirmThreshold) {
            bulkLaunchDialog.pendingSids = sids
            bulkLaunchDialog.open()
        } else {
            _runBulkLaunch(sids)
        }
    }

    function _runBulkLaunch(sids) {
        if (!appsModel) return
        // launchAppByStorageId fires closeRequested per call; the bulk path
        // calls the inner step directly so the close runs once at the end.
        for (var i = 0; i < sids.length; ++i)
            _launchOneBySid(sids[i])
        closeRequested()
    }

    function _runBulkHide(sids) {
        if (!appsModel) return
        for (var i = 0; i < sids.length; ++i)
            appsModel.hideByStorageId(sids[i])
        // Persist the new hidden-list to config so the change survives a
        // plasmoid reload (mirrors the single Hide handler).
        panel.configuration.hiddenApps = appsModel.hiddenApps
    }

    Kirigami.PromptDialog {
        id: bulkLaunchDialog
        property list<string> pendingSids: []
        title: i18nd("dev.xarbit.appgrid", "Launch all selected?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Open %1 application at once?",
            "Open %1 applications at once?",
            pendingSids.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: panel._runBulkLaunch(pendingSids)
    }

    Kirigami.PromptDialog {
        id: bulkHideDialog
        property list<string> pendingSids: []
        title: i18nd("dev.xarbit.appgrid", "Hide selected applications?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Hide %1 application from AppGrid? You can unhide it later in Settings → Hidden Applications.",
            "Hide %1 applications from AppGrid? You can unhide them later in Settings → Hidden Applications.",
            pendingSids.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: panel._runBulkHide(pendingSids)
    }
}
