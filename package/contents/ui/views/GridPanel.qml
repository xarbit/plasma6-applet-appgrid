/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Grid panel content shared by the two AppGrid hosts — the Panel applet and the
    standalone daemon. Always hosted inside a Plasma surface that draws its own
    themed background, blur and shadow, so the panel itself is a plain transparent,
    chromeless Item.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import dev.xarbit.appgrid.models

import "../controllers"
import "../widgets"
import "../js/favoriteid.js" as FavoriteId
import "../js/searchresultnav.js" as SearchResultNav
import "../js/constants.js" as Const
import "../js/gridmetrics.js" as GridMetrics
import "../js/prefixmodes.js" as PrefixModes
import "../js/scale.js" as Scale

Item {
    id: panel

    signal closeRequested()
    // Plasmoid root. Deliberately `var`, not typed as PlasmoidItem,
    // for two reasons: typing it would force every consumer to import
    // `org.kde.plasma.plasmoid`, and keeping the contract structural lets
    // tests pass plain QtObject mocks that expose the same properties
    // (dragSource, isDragInFlight, closeWindow(), favoritesDragProxy, …).
    property var appletInterface: null
    readonly property var dragSource: appletInterface ? appletInterface.dragSource : null

    function shakeAllIcons() {
        appGrid.shakeAllIcons()
        categoryGridView.shakeAllIcons()
    }

    // The launcher controller (AppGridController): its models and services.
    // Both hosts inject theirs (the panel applet's Plasmoid.controller, the
    // daemon's own); tests inject a plain object with the same names. Injected
    // rather than reached through Plasmoid.* so the panel doesn't grab its
    // dependencies from a global.
    required property var plasmoidBridge
    readonly property var appsModel: plasmoidBridge ? plasmoidBridge.appsModel : null
    readonly property var searchModel: plasmoidBridge ? plasmoidBridge.searchModel : null
    readonly property var runnerSourceModel: plasmoidBridge ? plasmoidBridge.runnerSourceModel : null
    // Null on distro packages, which have no update checker.
    readonly property var updateChecker: plasmoidBridge && plasmoidBridge.isUniversalBuild ? plasmoidBridge.updateChecker : null

    // Read-write handle to Plasmoid.configuration. Reads route through
    // ConfigCache (`cfg`) below; writes still target this handle directly
    // for the launch-bookkeeping flush (recents / launchCounts /
    // hiddenApps).
    required property var configuration

    // Supplied by the plasmoid root, forwarded to the prefix views (`i:`). A
    // function returning the system-info map, not the map itself, so the
    // /proc + os-release reads only run when the i: info view opens (#200).
    required property var sysInfoProvider

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

    // One-shot override set by the secondary "Open in Compact Mode" global
    // shortcut. While true, the panel behaves as if hideGridWhenEmpty were
    // enabled, regardless of the persisted config. Reset on close so the
    // next normal open uses the user's chosen mode.
    property bool forceCompact: false
    readonly property bool effectiveHideGridWhenEmpty: cfgHideGridWhenEmpty || forceCompact

    // -- Sort helpers --
    readonly property bool isSortByCategory: sortMode === AppFilterModel.ByCategory

    // -- View state --
    // hideGridWhenEmpty: Compact mode — suppress grid/category chrome
    // until the user types. Search and prefix views still take over once
    // the user starts entering text. _gridRevealed lets the user pop the
    // grid open manually (Down arrow from the search bar) without typing.
    // The five visibility outputs and the _gridRevealed flag all live on
    // visibility (VisibilityState.qml); the aliases below preserve the
    // existing call sites.
    readonly property bool isSearching: searchBar.text.length > 0
    // The views switch between grid and search list on the search the model
    // has actually been filtered with, not the live field text: the filter
    // pass is deferred (see SearchPipeline), and switching early showed the
    // search list on the unfiltered apps, or rebuilt the grid from the stale
    // search results before the restored filter landed.
    readonly property bool _searchApplied: viewState.searchText.length > 0
    readonly property bool isFavoritesActive: viewState.favorites

    // The selected tab and the applied search; the apps model's filter
    // follows from them (see ViewState).
    ViewState {
        id: viewState
        appsModel: panel.appsModel
        searchAll: cfg.searchAll
        isPrefixMode: panel.isPrefixMode
        categoryFilters: !panel.categoryFolders && !panel.isSortByCategory
    }

    VisibilityState {
        id: visibility
        sizeToContent: panel.sizeToContent
        hideGridWhenEmpty: panel.effectiveHideGridWhenEmpty
        showCategoryBar: panel.cfgShowCategoryBar
        isSearching: panel._searchApplied
        isPrefixMode: panel.isPrefixMode
        isFavoritesActive: panel.isFavoritesActive
        isSortByCategory: panel.isSortByCategory
        categoryFolders: panel.categoryFolders
        // A specific category tab is selected → fold that category in any sort.
        categoryFiltered: viewState.category.length > 0
    }

    // Folder tree needs the kmenuedit hierarchy, which only exists in system
    // categories mode (#201).
    readonly property bool categoryFolders: cfg.useSystemCategories && cfg.categoryFoldersEnabled

    property alias _gridRevealed: visibility.gridRevealed
    readonly property alias _emptyHiddenState: visibility.emptyHidden
    readonly property alias showCatBar: visibility.catBarVisible
    // The flat category-section grid (its many consumers keep this name); the
    // folder-tree variant is showMenuFolders.
    readonly property alias showCategoryGrid: visibility.categorySectionsVisible
    readonly property alias showMenuFolders: visibility.menuFolderVisible
    readonly property alias showAppGrid: visibility.appGridVisible

    // True while the menu folder view is inside a sub-folder — the variants' Esc
    // Shortcut yields to it so Esc climbs out a level instead of closing (#201),
    // just like favFolderOpen does for a favourites folder.
    readonly property bool menuFolderCanGoBack: showMenuFolders && menuFolderView.canGoBack
    // A drill folder (favourites or menu) is open, so Esc should climb out a level
    // rather than close — the variants' Escape Shortcut yields to this. One property
    // so a new drill context only touches GridPanel, not the window code.
    readonly property bool drillCanGoBack: favFolderOpen || menuFolderCanGoBack
    readonly property alias showSearchResults: visibility.searchResultsVisible

    readonly property string currentResultIcon: {
        if (!showSearchResults || !panel.searchModel || searchResultsList.count <= 0)
            return ""
        const idx = searchResultsList.currentIndex >= 0 ? searchResultsList.currentIndex : 0
        const icon = panel.searchModel.iconNameAt(idx)
        return icon.length > 0 ? icon : Const.DEFAULT_ICON
    }

    // Inline-completion suffix for the search field, shown ghosted and accepted
    // with Tab. Completes the typed text to the best matching *word* across the
    // ranked apps' name / generic name / keywords (AppFilterModel.completionFor)
    // — so "te" completes to "terminal" even when the top result is an app
    // named "Ghostty" that matched via its terminal keyword. Empty in prefix
    // mode or when nothing matches.
    readonly property string searchCompletion: {
        if (!cfg.searchInlineCompletion || !showSearchResults || panel.isPrefixMode || !panel.appsModel)
            return ""
        // Use the live field text (not the coalesced searchText): the ghost's
        // position tracks the caret every frame, so its content must update the
        // same frame or it visibly shakes. completionFor() only scans the top 25
        // rows, so it's cheap enough to run synchronously — the heavy filter pass
        // is what's deferred via Qt.callLater, not this.
        const q = searchBar.text
        if (q.length === 0)
            return ""
        const word = panel.appsModel.completionFor(q)
        return word.length > q.length ? word.substring(q.length) : ""
    }

    // The field text to the grid filter (deferred) and KRunner (debounced).
    SearchPipeline {
        id: searchPipeline
        viewState: viewState
        runnerSourceModel: panel.runnerSourceModel
        useExtraRunners: panel.cfgUseExtraRunners
        isPrefixMode: panel.isPrefixMode
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

    // -- Density scaler: drives content-sizing (fonts, secondary icons)
    // across the panel from the user's icon-size preference. Anchored at
    // Large=1.0 (the previous default) so existing-user appearance is
    // preserved; smaller icon presets scale content proportionally
    // smaller. Each consumer keeps its own intrinsic multiplier (e.g.
    // search field's 1.3, category button's 1.1) in code and applies
    // densityScale on top.
    // Control elements (close button, power buttons, pagination dots)
    // stay fixed. independentTextSize pins this to 1.0 so the Size preset
    // changes only the app icons, not text/spacing (#167). The curve and
    // the #167 gate live in Scale.textScale (single, tested policy).
    readonly property real densityScale: Scale.textScale(cfg.iconSize, cfg.independentTextSize)

    // -- Prefix mode detection --
    PrefixDetector { id: prefixDetector; input: searchBar.text }
    readonly property string prefixMode: prefixDetector.mode
    readonly property bool isPrefixMode: prefixDetector.isPrefixMode
    readonly property string prefixArgument: prefixDetector.argument

    property bool _needsScrollToTop: false

    // Raised by the "settings" header action; the host opens its settings
    // surface (the daemon's window, or the applet config for the panel variant).
    signal configureRequested()

    // Forwarded to VisibilityState: the daemon (sizeToContent) opts the grid into
    // compact-collapse-when-empty, so its fixed PlasmaWindow shrinks to the header
    // and grows when the grid reveals. The panel-plasmoid variant leaves it off —
    // Plasma owns the popup size; implicitHeight only seeds it.
    property bool sizeToContent: false

    // Icon-based estimate avoids the circular dependency panel width →
    // grid cellWidth → grid width → panel width. estCellHeight must match
    // AppGridView.cellHeight with labels visible (gridUnit too small per
    // row would accumulate and clip the bottom row).
    readonly property real estCellWidth: GridMetrics.labelledCellWidth(gridIconSize,
                                         Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing,
                                         densityScale, cfg.reduceGridSpacing)
    readonly property real estCellHeight: GridMetrics.labelledCellHeight(gridIconSize,
                                          Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, densityScale)

    readonly property real panelMargin: Kirigami.Units.largeSpacing
    readonly property real panelWidth: estCellWidth * columns + panelMargin * 2
    // Each full-height body view carries this as Layout.preferredHeight, so the
    // panel sizes to header(natural) + rows*cell — visible-rows honoured whatever
    // header chrome shows (#205).
    readonly property real bodyHeight: estCellHeight * rows

    // Full (grid-shown) height — used only to position the daemon window so a
    // start-compact reveal grows downward without drift. Real header items, no
    // units estimate.
    readonly property real panelHeight: panelMargin * 2 + headerRow.implicitHeight
        + Kirigami.Units.largeSpacing + bodyHeight
        + (showCatBar ? categoryBar.implicitHeight + Kirigami.Units.largeSpacing * 3 : 0)

    // Only seed the *initial* popup size via implicitWidth/Height and leave
    // width/height + preferred size unbound, so Plasma's own popup-resize
    // persistence owns it. A hard preferred-size binding re-asserted the estimate
    // on every layout pass (e.g. a monitor wake) and snapped the user's edge-drag
    // back, shrinking the popup (#146).
    implicitWidth: panelWidth
    // Natural content height — pixel-perfect, and compact (no body view visible)
    // collapses to header-only on its own (#205). Daemon window reads it; panel
    // popup seeds from it.
    implicitHeight: contentLayout.implicitHeight + panelMargin * 2

    Layout.preferredWidth: -1
    Layout.preferredHeight: -1
    Layout.minimumWidth: Kirigami.Units.gridUnit * 12
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12

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

    // Swallow right-clicks on empty panel area so they don't bubble up
    // to Plasma's containment ("Configure Widget", "Remove Widget", …) —
    // Kickoff / KRunner do the same so right-clicking inside the popup
    // never surfaces a widget-management menu. Child delegates (icons,
    // search rows, category items) install their own right-click
    // handlers and so win the gesture before this one fires. (#158)
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.WithinBounds
        onTapped: { }
    }

    // Pushes the persisted settings into the model. syncModelFromConfig stays as
    // the public entry point — the daemon calls it when the settings window edits
    // config. (Launch state — hidden/recent/counts — is synced separately
    // by AppGridController via the shared LaunchStateStore.)
    ModelConfigSync {
        id: modelSync
        appsModel: panel.appsModel
        cfg: cfg
    }
    function syncModelFromConfig() { modelSync.sync() }

    Component.onCompleted: {
        const _t0 = Date.now()
        syncModelFromConfig()
        _perfMark("coldBuild", _t0)
    }

    // -- KActivities-backed favorites (always the source of truth) --
    FavoritesManager {
        id: favorites
        sharedFavoritesModel: panel.plasmoidBridge ? panel.plasmoidBridge.favoritesModel : null
        favoritesGroupedModel: panel.favoritesGroupedModel
    }
    readonly property alias favoriteIdRole: favorites.favoriteIdRole
    readonly property alias sharedFavoritesModel: favorites.sharedFavoritesModel

    // Favourites folders (issue #18). The C++ grouped model (shared by both
    // variants via the bridge) composes KAStats favourites with the folder layout.
    // One model owns the favourites tab (alpha-sort off): the grouped model in
    // both grouping states. Its groupingEnabled flag (bound below from
    // favoriteFoldersEnabled) folds folders into tiles or expands them inline, so
    // toggling grouping keeps a single layout and order (issue #200).
    readonly property var favoritesGroupedModel: panel.plasmoidBridge
        ? panel.plasmoidBridge.favoritesGroupedModel : null
    readonly property bool useFavoritesGrouped: favoritesGroupedModel && !cfg.sortFavoritesAlphabetically
    Binding {
        target: panel.favoritesGroupedModel
        property: "groupingEnabled"
        value: cfg.favoriteFoldersEnabled
        when: panel.favoritesGroupedModel
        restoreMode: Binding.RestoreNone
    }
    // The model that drives the main grid: the grouped favourites model on the
    // favourites tab, else the filtered app model (All / categories / alpha-sorted
    // favourites).
    readonly property var gridModel: !isFavoritesActive ? appsModel
        : (useFavoritesGrouped ? favoritesGroupedModel : appsModel)
    // Favourites drills in place (#18): the same DrillNavigator the menu view uses,
    // so the back-focus / canGoBack behaviour is identical. favFolderOpen feeds the
    // variants' Escape Shortcut (it yields while inside a favourites folder).
    readonly property bool favFolderOpen: isFavoritesActive && favDrillNav.canGoBack
    DrillNavigator {
        id: favDrillNav
        model: panel.favoritesGroupedModel
        grid: appGrid
        active: panel.isFavoritesActive
    }
    Connections {
        target: panel.favoritesGroupedModel
        ignoreUnknownSignals: true
        // Prompt for a name as soon as a folder is created (drag-fold, menu, empty).
        function onFolderCreated(folderId) { dialogs.renameFolder(folderId) }
    }
    // Leaving the favourites tab drops back to the folder top level.
    onIsFavoritesActiveChanged: if (!isFavoritesActive && favoritesGroupedModel) favoritesGroupedModel.resetToRoot()

    // #193: drop a favorite into the launcher's empty space (anywhere that isn't
    // the favorites grid, but inside the window) to remove it. Lowest z, so the
    // grid's own reorder DropArea catches reorders first; a drop the compositor
    // routes outside the window never reaches here, so it stays put. Acts only on
    // an own drag whose source is actually a favorite — other drops fall through.
    // Dropping a dragged favourite or folder on empty space removes it.
    FavoriteRemoveArea {
        anchors.fill: parent
        z: -10
        // Only while the favourites grid is on screen (its whole purpose): in
        // any other view, dragging an app that happens to be a favourite must
        // not arm a red ✕ across the grid.
        enabled: panel.sharedFavoritesModel !== null && panel.isFavoritesActive
        dragSource: panel.dragSource
        favoritesModel: panel.sharedFavoritesModel
        favoritesGroupedModel: panel.favoritesGroupedModel
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
        contextMenu.close()
        categoryBar.closeCategoryMenu()
        headerActions.closeMenus()
        categoryBar.resetScroll()
        _resetSearchSession()
        // Don't reopen the last folder on the next launch (#18).
        if (favoritesGroupedModel) favoritesGroupedModel.resetToRoot()
        // The visible state reset happens HERE, while the popup is hidden behind
        // the fade-out, so the next open shows a clean grid instead of flashing
        // the refresh as it appears.
        _applyStartState()
        _resetGridUiState()
    }

    // Start tab + cleared live filter. Idempotent — the model setters no-op when
    // the value is unchanged — so it's safe to run on open too: it reflects a
    // config change made while closed without refreshing when nothing changed.
    function _applyStartState() {
        viewState.reset(cfgShowCategoryBar && cfgStartWithFavorites)
    }

    // Pure UI-state reset (scroll, selection, category view). Close-only: running
    // it on open would visibly jump the grid as the popup appears.
    function _resetGridUiState() {
        categoryBar.altHeld = false
        appGrid.clearShuffles()
        appGrid.selection.clear()
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        searchResultsList.currentIndex = 0
        categoryGridView.resetView()
        // Clear all navigation so the next open starts clean (the tab and filter
        // went back to the start in _applyStartState): the menu tree back to
        // all-categories, and any open favourites folder closed.
        if (categoryFolders && plasmoidBridge && plasmoidBridge.menuTreeModel)
            plasmoidBridge.menuTreeModel.setRootPath("")
        if (favoritesGroupedModel)
            favoritesGroupedModel.resetToRoot()
        // Clear the drill views' scroll + nav memory so the next open doesn't flash
        // the last folder before snapping back.
        favDrillNav.reset()
        menuFolderView.reset()
        _needsScrollToTop = true
    }

    // Perf instrumentation for the open path (#200). console.debug is silent
    // unless QML debug logging is on: QT_LOGGING_RULES="qml.debug=true".
    function _perfMark(label, since) { console.debug("[appgrid.perf]", label, (Date.now() - since), "ms") }

    // -- Reset state (called when showing the grid) --
    function resetState() {
        const _t0 = Date.now()
        contextMenu.close()
        categoryBar.closeCategoryMenu()
        headerActions.closeMenus()
        _resetSearchSession()

        // The heavy grid UI reset (scroll/selection/category view) already ran on
        // the previous close, while hidden. Here we only pick up config that may
        // have changed while closed (sort, columns, default-tab) and re-apply the
        // start tab/filter — both idempotent, so an unchanged-config open does no
        // visible refresh. Default apps refresh on KSycoca/kdeglobals, not here (#200).
        syncModelFromConfig()
        _applyStartState()

        focusSearchField()
        _perfMark("resetState", _t0)
    }

    // Give the search field keyboard focus so typing searches right away.
    function focusSearchField() {
        searchBar.field.forceActiveFocus()
    }

    // Launch routing (single + bulk, the KActivities broadcast, the bulk
    // confirm threshold) lives in the coordinator; the panel keeps the UI side
    // effects it signals — the search-field paste and the two confirm dialogs.
    // The functions below stay as the call sites' entry points.
    LaunchCoordinator {
        id: launcher
        appsModel: panel.appsModel
        searchModel: panel.searchModel
        plasmoidBridge: panel.plasmoidBridge
        onCloseRequested: panel.closeRequested()
        onSubstitutionRequested: function(text) {
            searchBar.field.text = text
            searchBar.field.cursorPosition = text.length
        }
        onBulkLaunchConfirmRequested: function(sids, fromFolder) {
            dialogs.confirmBulkLaunch(sids, fromFolder)
        }
    }
    function launchSearchResult(index) { launcher.launchSearchResult(index) }
    function launchApp(index) { launcher.launchApp(index) }
    function launchAppByStorageId(sid) { launcher.launchAppByStorageId(sid) }
    function _requestBulkLaunch(sids, fromFolder = false) { launcher.requestBulkLaunch(sids, fromFolder) }
    function _runBulkLaunch(sids) { launcher.runBulkLaunch(sids) }

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
        id: contentLayout
        anchors.fill: parent
        anchors.margins: panel.panelMargin
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            // Pin the row height so it does not shrink when the power
            // buttons hide on search — implicitHeight ignores hidden
            // children, so derive it from both regardless of visibility.
            Layout.preferredHeight: Math.max(searchBar.implicitHeight,
                                             headerActions.actionsImplicitHeight)

            SearchBar {
                id: searchBar
                objectName: "searchBar"
                // Hide the X while the header slot is mid-animation so it
                // doesn't appear to slide in from the right with the
                // growing field; snaps in once the layout settles.
                clearButtonEnabled: !headerActions.animRunning
                // Track icon-size preference: small icons → smaller search
                // field, large icons → larger. Keeps placeholder text in
                // proportion with grid labels without a separate setting (#163).
                fontScale: panel.densityScale
                completion: panel.searchCompletion

                onTextChanged: searchPipeline.setText(text)
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
                    if (panel.prefixMode === PrefixModes.TERMINAL) {
                        panel.plasmoidBridge.systemActions.runInTerminal(panel.prefixArgument, cfg.terminalShell)
                        panel.closeRequested()
                    } else if (panel.prefixMode === PrefixModes.COMMAND) {
                        panel.plasmoidBridge.systemActions.runCommand(panel.prefixArgument, cfg.terminalShell)
                        panel.closeRequested()
                    } else if (panel.prefixMode === PrefixModes.FILES) {
                        prefixModeLoader.item?.activateFileCurrent()
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
                        if (categoryGridView.appIndex < 0) {
                            categoryGridView.selectFirst()
                        } else {
                            categoryGridView.ensureVisible()
                        }
                    } else if (panel.showMenuFolders) {
                        menuFolderView.focusGrid()
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
                    if (panel.prefixMode === PrefixModes.FILES) {
                        prefixModeLoader.item?.focusFileList()
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

            HeaderActions {
                id: headerActions
                Layout.alignment: Qt.AlignVCenter
                isSearching: panel.isSearching
                showSearchResults: panel.showSearchResults
                currentResultIcon: panel.currentResultIcon
                densityScale: panel.densityScale
                showActionLabels: cfg.showActionLabels
                hideMenuButtonLabel: cfg.hideMenuButtonLabel
                headerActions: cfg.headerActions
                customHeaderActions: cfg.customHeaderActions
                commandRunner: panel.plasmoidBridge ? panel.plasmoidBridge.systemActions : null
                terminalShell: cfg.terminalShell
                menuButtonIcon: cfg.menuButtonIcon
                iconShadow: cfg.iconShadow
                updateChecker: panel.updateChecker
                sessionActions: sessionActions
                onActionTriggered: panel.closeRequested()
                onConfigureRequested: panel.configureRequested()
            }
        }

        HorizontalDivider {
            Layout.fillWidth: true
            visible: panel.showCatBar
            opacity: panel.cfgShowDividers ? 1 : 0
        }

        CategoryBar {
            id: categoryBar
            visible: panel.showCatBar
            Layout.leftMargin: Kirigami.Units.smallSpacing
            appsModel: panel.appsModel
            isFavorite: sid => panel.sharedFavoritesModel
                               && panel.sharedFavoritesModel.isFavorite(FavoriteId.toPrefixed(sid))
            editCategoryInMenu: launcherActions.editMenuItem
            favoritesFirst: panel.cfgStartWithFavorites
            isSortByCategory: panel.isSortByCategory
            fontScale: panel.densityScale
            displayMode: cfg.categoryBarDisplay
            hideEmptyCategories: cfg.hideEmptyCategories
            openOnHover: cfg.openCategoryOnHover
            // The bar shows the view state and asks to change it. Leaving
            // favourites goes through categorySelected (All or a category), so
            // the scroll/reset of the sections grid happens once there.
            favoritesActive: viewState.favorites
            selectedCategory: viewState.category
            onFavoritesToggled: function(active) {
                viewState.selectFavorites(active)
                searchBar.field.forceActiveFocus()
            }
            // One feature across all sorts: flat sorts filter the grid (the view
            // state does that), folders root the tree, By Category scrolls to the
            // section.
            onCategorySelected: function(name) {
                viewState.selectCategory(name)
                searchBar.field.forceActiveFocus()
                if (panel.categoryFolders) {
                    const menuModel = panel.plasmoidBridge ? panel.plasmoidBridge.menuTreeModel : null
                    if (menuModel)
                        menuModel.setRootPath(name !== "" && panel.appsModel
                                              ? panel.appsModel.categoryMenuPath(name) : "")
                } else if (panel.isSortByCategory) {
                    if (name !== "")
                        Qt.callLater(function() { categoryGridView.scrollToCategory(name) })
                    else
                        categoryGridView.resetView()
                }
            }
        }

        HorizontalDivider {
            Layout.fillWidth: true
            visible: panel.showCatBar
            opacity: panel.cfgShowDividers ? 1 : 0
        }

        // -- Prefix mode view --
        // Built only when the user actually enters a prefix mode (#200). The
        // five sub-views (file browser, terminal, info, help, hidden) are rare,
        // so instantiating them eagerly only weighed down cold open.
        Loader {
            id: prefixModeLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            active: panel.isPrefixMode
            visible: active
            sourceComponent: PrefixModeView {
                mode: panel.prefixMode
                argument: panel.prefixArgument
                searchField: searchBar.field
                showScrollbars: cfg.showScrollbars
                appsModel: panel.appsModel
                listDirectory: path => panel.plasmoidBridge.systemActions.listDirectory(path)
                sysInfoProvider: panel.sysInfoProvider
                updateChecker: panel.updateChecker
                onFileOpened: panel.closeRequested()
                onDirectoryNavigated: function(path) {
                    searchBar.text = path
                }
            }
        }

        AnswerToEverything {
            queryText: searchBar.text
            resultsActive: panel.showSearchResults && !panel.isPrefixMode
            iconSize: panel.gridIconSize
        }

        SearchResultsList {
            id: searchResultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            visible: panel.showSearchResults
            PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
            model: panel._searchApplied ? panel.searchModel : null
            iconSize: panel.gridIconSize
            fontScale: panel.densityScale
            showDividers: panel.cfgShowDividers
            shadowEnabled: cfg.iconShadow
            showShortcuts: cfg.showSearchShortcuts
            animateHighlight: cfg.hoverAnimation !== Const.HoverAnimation.None
            searchField: searchBar.field
            favoritesManager: favorites
            plasmoidBridge: panel.plasmoidBridge
            onLaunched: function(index) { panel.launchSearchResult(index) }
            onContextMenuRequested: function(index, storageId, desktopFile) {
                // search-results has no multi-select; passing canSelect=false
                // hides the otherwise-no-op "Add to Selection" item.
                if (storageId)
                    contextMenu.showForApp(storageId, desktopFile, [], false)
            }
            onRunnerContextMenuRequested: function(index) {
                var item = panel.searchModel.get(index)
                if (!item) return
                var actions = panel.searchModel.runnerActions(index)
                // runner.favoriteId maps via the runner submodel, so it takes the
                // runner-row index (unified row minus the app count), the same
                // sourceIndex showForRunner uses — not the raw unified index.
                var favoriteId = panel.plasmoidBridge.runner.favoriteId(item.sourceIndex)
                contextMenu.showForRunner(item.sourceIndex, actions, favoriteId)
            }
        }

        // Flat category sections (the By Category sort).
        CategoryGridView {
            id: categoryGridView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            visible: panel.showCategoryGrid
            PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
            searchField: searchBar.field
            appsModel: panel.appsModel
            rowsModel: panel.plasmoidBridge ? panel.plasmoidBridge.categoryRowsModel : null
            cellWidth: Math.floor(categoryGridView.width / panel.columns)
            cellHeight: GridMetrics.labelledCellHeight(panel.gridIconSize,
                        Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, panel.densityScale)
            iconSize: panel.gridIconSize
            fontScale: panel.densityScale
            hoverAnimation: cfg.hoverAnimation
            shadowEnabled: cfg.iconShadow
            hoverHighlight: cfg.hoverHighlight
            showDividers: panel.cfgShowDividers
            showTooltips: panel.cfgShowTooltips
            showNewAppBadge: panel.cfgShowNewAppBadge
            dragSource: panel.dragSource
            showRecents: panel.cfgShowRecentApps
                         && panel.appsModel
                         && panel.appsModel.recentApps.length > 0
                         && !panel.isFavoritesActive
                         && !panel.cfgStartWithFavorites
            onLaunched: function(proxyIndex) { panel.launchApp(proxyIndex) }
            onRecentLaunched: function(storageId) { panel.launchAppByStorageId(storageId) }
            onCategoryNavRequested: function(direction) { panel.navigateCategory(direction) }
            onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
            onContextMenuRequested: function(proxyIndex, storageId, desktopFile) {
                contextMenu.showForApp(storageId, desktopFile,
                                       categoryGridView.selection.sidList())
            }
        }

        // -- Menu folder tree (By Category + group into folders, #201) --
        MenuFolderView {
            id: menuFolderView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            visible: panel.showMenuFolders
            // Gated on the feature so the (lazy) menu tree is never built when
            // folders are off — reading menuTreeModel is what triggers the walk.
            menuModel: panel.categoryFolders && panel.plasmoidBridge ? panel.plasmoidBridge.menuTreeModel : null
            appsModel: panel.appsModel
            sharedFavoritesModel: panel.sharedFavoritesModel
            favoritesManager: favorites
            favoriteIdRole: panel.favoriteIdRole
            dragSource: panel.dragSource
            columns: panel.columns
            iconSize: panel.gridIconSize
            fontScale: panel.densityScale
            reduceGridSpacing: cfg.reduceGridSpacing
            shadowEnabled: cfg.iconShadow
            hoverAnimation: cfg.hoverAnimation
            hoverHighlight: cfg.hoverHighlight
            showScrollbars: cfg.showScrollbars
            hideEmpty: cfg.hideEmptyCategories
            searchField: searchBar.field
            onLaunched: function(sid) { panel.launchAppByStorageId(sid) }
            onCategoryNavRequested: function(direction) { panel.navigateCategory(direction) }
            onFolderContextRequested: function(menuPath) { menuFolderContextMenu.showFor(menuPath) }
            onAppContextRequested: function(sid, desktopFile, selectedSids) {
                contextMenu.showForApp(sid, desktopFile, selectedSids)
            }
            onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
        }

        // -- App grid (favourites / all / category). Favourites folders drill in
        // place via the shared DrillBar instead of a popup overlay (#18). --
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            visible: panel.showAppGrid
            spacing: Kirigami.Units.smallSpacing

            // Back + breadcrumb while inside a favourites folder; drag a member
            // onto it to remove it from the folder.
            DrillBar {
                Layout.fillWidth: true
                model: panel.favoritesGroupedModel
                dragSource: panel.dragSource
                editable: true
                visible: panel.isFavoritesActive && panel.favFolderOpen
                onRemoveMemberRequested: function(sid) {
                    if (panel.favoritesGroupedModel)
                        panel.favoritesGroupedModel.removeFromFolder(panel.favoritesGroupedModel.currentPath, sid)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

            // Favourites come from KActivities, which may still be starting on a
            // cold boot; show a loading state instead of an empty grid until the
            // store is ready.
            Kirigami.LoadingPlaceholder {
                anchors.centerIn: parent
                z: 1
                visible: panel.isFavoritesActive && panel.sharedFavoritesModel
                         && !panel.sharedFavoritesModel.enabled
            }

            AppGridView {
                id: appGrid
                anchors.fill: parent
                PlasmaComponents.ScrollBar.vertical: OverlayScrollBar { showScrollbars: cfg.showScrollbars }
                model: panel._searchApplied ? null : panel.gridModel
                appsModel: panel.appsModel
                sharedFavoritesModel: panel.sharedFavoritesModel
                favoritesGroupedModel: panel.favoritesGroupedModel
                // Editable here (unlike the read-only menu tree).
                groupedModel: panel.favoritesGroupedModel
                favoritesManager: favorites
                // Folders drill in place; Esc climbs back out (the window Shortcut
                // yields via favFolderOpen, like the menu view).
                onOpenFolderRequested: function(folderId) {
                    if (panel.favoritesGroupedModel)
                        panel.favoritesGroupedModel.enterFolder(folderId)
                }
                onEscapePressed: favDrillNav.goBack()
                onFolderContextMenuRequested: folderId => contextMenu.showForFolder(folderId)
                onEmptyAreaContextMenuRequested: contextMenu.showForEmptyArea()
                favoriteIdRole: panel.favoriteIdRole
                dragSource: panel.dragSource
                columns: panel.columns
                adaptiveColumns: true
                iconSize: panel.gridIconSize
                fontScale: panel.densityScale
                reduceGridSpacing: cfg.reduceGridSpacing
                hoverAnimation: cfg.hoverAnimation
                shadowEnabled: cfg.iconShadow
                hoverHighlight: cfg.hoverHighlight
                sortFavoritesAlphabetically: cfg.sortFavoritesAlphabetically
                searchField: searchBar.field
                showRecentApps: panel.cfgShowRecentApps
                startWithFavorites: panel.cfgStartWithFavorites
                favoritesActive: panel.isFavoritesActive
                showDividers: panel.cfgShowDividers
                showTooltips: panel.cfgShowTooltips
                showNewAppBadge: panel.cfgShowNewAppBadge
                hideLabelsOnFavorites: panel.cfgHideLabelsOnFavorites
                animateHighlight: cfg.hoverAnimation !== Const.HoverAnimation.None
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
                    contextMenu.showForApp(storageId, desktopFile,
                                           appGrid.selection.sidList())
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
    }


    LauncherActions {
        id: launcherActions
        taskManager: panel.plasmoidBridge ? panel.plasmoidBridge.plasmoidClient : null
        desktop: panel.plasmoidBridge ? panel.plasmoidBridge.systemActions : null
    }

    // Right-click menu for a menu-tree folder (#201): open it, launch the apps
    // directly in it (not its subfolders'), or edit it in kmenuedit, the same
    // action the category bar offers per category.
    FolderContextMenu {
        id: menuFolderContextMenu
        readonly property var _menuModel: panel.plasmoidBridge ? panel.plasmoidBridge.menuTreeModel : null
        appIdsOf: id => _menuModel ? _menuModel.folderAppIds(id) : []
        onOpenRequested: folderId => { if (_menuModel) _menuModel.enterFolder(folderId) }
        onLaunchAllRequested: appIds => panel._requestBulkLaunch(appIds, true)

        AppGridMenuItem {
            text: i18nd("dev.xarbit.appgrid", "Edit in Menu Editor…")
            icon.name: "kmenuedit"
            onClicked: launcherActions.editMenuItem(menuFolderContextMenu.folderId)
        }
    }

    SessionActions { id: sessionActions }

    AppContextMenu {
        id: contextMenu
        appsModel: panel.appsModel
        sharedFavoritesModel: panel.sharedFavoritesModel
        // Always available so "Add to Folder" works for a favourite right-clicked
        // anywhere (grid, search) — not only on the favourites tab.
        favoritesGroupedModel: panel.favoritesGroupedModel
        favoritesManager: favorites
        foldersEnabled: cfg.favoriteFoldersEnabled
        enableActivities: cfg.enableActivities
        favoritesActive: panel.isFavoritesActive
        appletInterface: panel.appletInterface
        onOpenFolderRequested: folderId => { if (panel.favoritesGroupedModel) panel.favoritesGroupedModel.enterFolder(folderId) }
        onRenameFolderRequested: folderId => dialogs.renameFolder(folderId)
        onFolderLaunchRequested: sids => panel._requestBulkLaunch(sids, true)

        // Wrap the bridge's C++ methods in closures (not bare refs): called as
        // contextMenu.<prop>() the bare ref would run with the menu as `this`, not
        // the bridge — Qt6 warns about that (NativeMethodBehavior). The arrow binds
        // the call back to plasmoidBridge.
        appActions: sid => panel.plasmoidBridge.launchService.appActions(sid)
        launchAppAction: (sid, actionName) => panel.plasmoidBridge.launchService.launchAction(sid, actionName)
        canManageInDiscover: sid => panel.plasmoidBridge.systemActions.canManageInDiscover(sid)
        openInDiscover: sid => panel.plasmoidBridge.systemActions.openInDiscover(sid)
        pinToTaskManager: launcherActions.pinToTaskManager
        addToDesktop: launcherActions.addToDesktop
        canPinToTaskManager: launcherActions.canPinToTaskManager
        canAddToDesktop: launcherActions.canAddToDesktop
        editApplication: launcherActions.editMenuItem
        runRunnerAction: function(rowIdx, actIdx) {
            if (panel.plasmoidBridge.runner.runAction(rowIdx, actIdx))
                closeRequested()
        }

        onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
        onBulkHideRequested: function(sids) {
            if (!sids || sids.length === 0) return
            dialogs.confirmBulkHide(sids)
        }

        // Route the menu's "Add / Remove from Selection" item to whichever
        // grid currently owns the selection state. Resolved via the
        // panel.activeMultiSelectView binding — search results and recents
        // resolve to null, so the toggle silently no-ops there.
        onToggleSelectionRequested: function(sid) {
            const v = panel.activeMultiSelectView
            if (v && sid) v.selection.toggleSelectionBySid(sid)
        }
        onClearSelectionRequested: {
            const v = panel.activeMultiSelectView
            if (v) v.selection.clear()
        }
    }

    // Confirmations and the folder rename.
    LauncherDialogs {
        id: dialogs
        anchors.fill: parent
        favoritesGroupedModel: panel.favoritesGroupedModel
        onBulkLaunchAccepted: sids => launcher.runBulkLaunch(sids)
        onBulkHideAccepted: sids => launcher.runBulkHide(sids)
    }
}
