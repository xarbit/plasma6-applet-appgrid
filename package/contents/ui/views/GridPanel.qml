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

    // C++ models supplied by the owning plasmoid root. Injected here
    // rather than reached through Plasmoid.* so the panel doesn't grab
    // its dependencies from a global and so tests can pass stubs.
    required property var appsModel
    required property var searchModel
    required property var runnerSourceModel

    // Read-write handle to Plasmoid.configuration. Reads route through
    // ConfigCache (`cfg`) below; writes still target this handle directly
    // for the launch-bookkeeping flush (recents / launchCounts /
    // hiddenApps).
    required property var configuration

    // The plasmoid-callback surface (methods + favoritesGroupedModel / isWayland).
    // Panel injects the applet (Plasmoid), standalone injects its controller; both
    // implement the same Q_PROPERTY / Q_INVOKABLE interface. Tests inject a plain
    // QtObject stub with the same names.
    required property var plasmoidBridge

    // Update-checker handle (null on distro packages); forwarded to HeaderActionStrip.
    required property var updateChecker

    // KAStats favorites client id, built from the plasmoid id at the root.
    required property string favoritesClientInstance

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
    readonly property bool isSortByCategory: sortMode === Const.SortMode.ByCategory

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
        sizeToContent: panel.sizeToContent
        hideGridWhenEmpty: panel.effectiveHideGridWhenEmpty
        showCategoryBar: panel.cfgShowCategoryBar
        isSearching: panel.isSearching
        isPrefixMode: panel.isPrefixMode
        isFavoritesActive: panel.isFavoritesActive
        isSortByCategory: panel.isSortByCategory
        categoryFolders: panel.categoryFolders
        // A specific category tab is selected → fold that category in any sort.
        categoryFiltered: categoryBar.selectedCategory.length > 0
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

    // The grid filter + ranking is the heavy per-keystroke work. Coalesce it
    // through Qt.callLater so a burst of fast keystrokes triggers a single
    // filter pass after input settles, never blocking the text field itself.
    property string _pendingSearchText: ""
    function _applySearchText() {
        searchSession.update(panel._pendingSearchText)
    }

    // Trailing-debounce window for continued typing into KRunner. Short enough to
    // feel live, long enough to collapse a fast-typed query into a single runner
    // query (ResultsModel runs every enabled runner in-process per query).
    readonly property int _runnerDebounceMs: 50

    // Push the current field text to KRunner (or clear it). Shared by the
    // leading-edge fire and the trailing debounce.
    function _applyRunnerQuery() {
        if (!panel.runnerSourceModel)
            return
        const q = searchBar.text
        const searching = q.length > 0 && !panel.isPrefixMode && panel.cfgUseExtraRunners
        panel.runnerSourceModel.queryString = searching ? q : ""
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
        appsModel: panel.appsModel
        favoritesGroupedModel: panel.favoritesGroupedModel
        clientInstance: panel.favoritesClientInstance
        sortFavoritesAlphabetically: cfg.sortFavoritesAlphabetically
    }
    readonly property alias favoriteIdRole: favorites.favoriteIdRole
    readonly property alias sharedFavoritesModel: favorites.sharedFavoritesModel
    readonly property alias mirrorRequired: favorites.mirrorRequired

    // Favourites folders (issue #18). The C++ grouped model (shared by both
    // variants via the bridge) composes KAStats favourites with the folder layout.
    // The folder grid is used only on the favourites tab, with folders enabled and
    // alpha-sort off (KAStats order is authoritative there, not the folder layout).
    readonly property var favoritesGroupedModel: panel.plasmoidBridge
        ? panel.plasmoidBridge.favoritesGroupedModel : null
    readonly property bool useFolderGrid: cfg.favoriteFoldersEnabled
                                          && favoritesGroupedModel
                                          && !cfg.sortFavoritesAlphabetically
    // The model that drives the main grid: the grouped folders model on the
    // favourites tab, else the flat KAStats favourites (manual order), else the
    // filtered app model (All / categories / alpha-sorted favourites).
    readonly property var gridModel: !isFavoritesActive ? appsModel
        : (useFolderGrid ? favoritesGroupedModel
           : (sharedFavoritesModel && !cfg.sortFavoritesAlphabetically ? sharedFavoritesModel : appsModel))
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
        function onFolderCreated(folderId) { renameFolderDialog.openFor(folderId) }
    }
    // Leaving the favourites tab drops back to the folder top level.
    onIsFavoritesActiveChanged: if (!isFavoritesActive && favoritesGroupedModel) favoritesGroupedModel.resetToRoot()

    // #193: drop a favorite into the launcher's empty space (anywhere that isn't
    // the favorites grid, but inside the window) to remove it. Lowest z, so the
    // grid's own reorder DropArea catches reorders first; a drop the compositor
    // routes outside the window never reaches here, so it stays put. Acts only on
    // an own drag whose source is actually a favorite — other drops fall through.
    DropArea {
        id: favoriteRemoveArea
        anchors.fill: parent
        z: -10
        // Drag-OUT removal only makes sense while the favourites grid is on
        // screen (its whole purpose). In any other view dragging an app that
        // happens to be a favourite must not arm a red ✕ across the grid (the
        // forbidden-over-tab case is handled by the tab hover instead).
        enabled: panel.sharedFavoritesModel !== null && panel.isFavoritesActive

        // The dragged sids that are actually favorites (empty unless this is an
        // own drag with at least one favorite source). Drives both the ✕ marker
        // and the drop removal.
        function _favoriteSids(drag) {
            const src = panel.dragSource
            if (!src || src.blockedOnFavoritesTab || !src.isOwnDrag(drag) || !panel.sharedFavoritesModel) {
                return []
            }
            const all = src.sourceStorageIds.length > 0 ? src.sourceStorageIds : [src.sourceStorageId]
            return all.filter(sid => sid && panel.sharedFavoritesModel.isFavorite(FavoriteId.toPrefixed(sid)))
        }

        // The dragged folder's id, if a folder cell is being dragged here (#18).
        function _folderId(drag) {
            const src = panel.dragSource
            return (src && !src.blockedOnFavoritesTab && src.isOwnDrag(drag)) ? (src.sourceFolderId || "") : ""
        }

        // Both helpers above return empty while blockedOnFavoritesTab is set, so
        // nothing here arms or removes — the drop over the Favorites tab cancels.
        function _removable(drag) {
            return _favoriteSids(drag).length > 0 || _folderId(drag).length > 0
        }

        // Hovering empty space with a favorite/folder drag arms removal: flag the
        // drag source (the cell shows a ✕) and accept so the cursor reads
        // droppable. onExited reverts when the cursor returns to the grid.
        onEntered: drag => {
            if (favoriteRemoveArea._removable(drag)) {
                panel.dragSource.dropWillRemove = true
                drag.accept(Qt.MoveAction)
            } else {
                // Not a removable drag (e.g. blocked over the Favorites tab):
                // reject so the platform shows the forbidden indicator instead
                // of a droppable cursor.
                drag.accepted = false
            }
        }
        onPositionChanged: drag => {
            if (favoriteRemoveArea._removable(drag))
                drag.accept(Qt.MoveAction)
            else
                drag.accepted = false
        }
        onExited: { if (panel.dragSource) panel.dragSource.dropWillRemove = false }

        onDropped: drag => {
            // A folder dropped here is dissolved (members return to favourites),
            // the folder equivalent of removing an icon.
            const folderId = favoriteRemoveArea._folderId(drag)
            if (folderId.length > 0 && panel.favoritesGroupedModel) {
                panel.favoritesGroupedModel.ungroupFolder(folderId)
                drag.accept(Qt.MoveAction)
                return
            }
            const sids = favoriteRemoveArea._favoriteSids(drag)
            if (sids.length === 0) {
                return
            }
            for (var i = 0; i < sids.length; ++i) {
                panel.sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(sids[i]))
            }
            drag.accept(Qt.MoveAction)
        }
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
        const startFav = cfgShowCategoryBar && cfgStartWithFavorites
        categoryBar.favoritesActive = startFav
        categoryBar.selectedCategory = ""
        if (appsModel) {
            appsModel.searchText = ""
            appsModel.filterCategory = ""
            appsModel.showFavoritesOnly = startFav
        }
    }

    // Pure UI-state reset (scroll, selection, category view). Close-only: running
    // it on open would visibly jump the grid as the popup appears.
    function _resetGridUiState() {
        categoryBar.altHeld = false
        categoryBar.selectedCategory = ""
        appGrid.clearShuffles()
        appGrid.clearSelection()
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        searchResultsList.currentIndex = 0
        categoryGridView.resetView()
        // Clear all navigation so the next open starts clean: category filter back
        // to All, the menu tree back to all-categories, and any open favourites
        // folder closed.
        if (appsModel)
            appsModel.filterCategory = ""
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

        searchBar.field.forceActiveFocus()
        _perfMark("resetState", _t0)
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
        onBulkLaunchConfirmRequested: function(sids) {
            bulkLaunchDialog.pendingSids = sids
            bulkLaunchDialog.open()
        }
    }
    function launchSearchResult(index) { launcher.launchSearchResult(index) }
    function launchApp(index) { launcher.launchApp(index) }
    function launchAppByStorageId(sid) { launcher.launchAppByStorageId(sid) }
    function _requestBulkLaunch(sids) { launcher.requestBulkLaunch(sids) }

    // Launch every app in a folder. Unlike the plain bulk path, each member is
    // launched favourite-aware (a KCM goes through KAStats, not the app
    // launcher), and the "open many at once?" threshold still applies (#18).
    function launchFolder(folderId) {
        const members = panel.favoritesGroupedModel
            ? panel.favoritesGroupedModel.folderMembers(folderId) : []
        if (members.length === 0)
            return
        if (members.length >= launcher.bulkLaunchConfirmThreshold) {
            folderLaunchDialog.pendingMembers = members
            folderLaunchDialog.open()
        } else {
            panel._launchFolderMembers(members)
        }
    }
    function _launchFolderMembers(members) {
        for (var i = 0; i < members.length; ++i)
            appGrid.launchFavoriteNoClose(members[i])
        panel.closeRequested()
    }
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
                // Hide the X while the header slot is mid-animation so it
                // doesn't appear to slide in from the right with the
                // growing field; snaps in once the layout settles.
                clearButtonEnabled: !headerActions.animRunning
                // Track icon-size preference: small icons → smaller search
                // field, large icons → larger. Keeps placeholder text in
                // proportion with grid labels without a separate setting (#163).
                fontScale: panel.densityScale
                completion: panel.searchCompletion

                // Trailing debounce for continued typing: collapses a fast-typed
                // query's keystrokes into one runner query.
                Timer {
                    id: runnerDebounce
                    interval: panel._runnerDebounceMs
                    onTriggered: panel._applyRunnerQuery()
                }

                onTextChanged: {
                    // Defer the grid filter/ranking so the field never blocks on
                    // it; rapid keystrokes coalesce into one pass (Qt.callLater
                    // collapses repeat calls within an event-loop iteration).
                    panel._pendingSearchText = text
                    Qt.callLater(panel._applySearchText)

                    var searching = text.length > 0 && !panel.isPrefixMode

                    // KRunner query (expensive: runs every enabled runner
                    // in-process) only runs with extra runners on.
                    if (searching && panel.cfgUseExtraRunners) {
                        // Leading edge: the first char of a fresh query (KRunner
                        // still idle) fires immediately so results start landing at
                        // once; subsequent keystrokes ride the trailing debounce.
                        if (panel.runnerSourceModel && panel.runnerSourceModel.queryString.length === 0) {
                            runnerDebounce.stop()
                            panel._applyRunnerQuery()
                        } else {
                            runnerDebounce.restart()
                        }
                    } else if (panel.runnerSourceModel) {
                        runnerDebounce.stop()
                        panel.runnerSourceModel.queryString = ""
                    }
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
                    if (panel.prefixMode === PrefixModes.TERMINAL) {
                        panel.plasmoidBridge.runInTerminal(panel.prefixArgument, cfg.terminalShell)
                        panel.closeRequested()
                    } else if (panel.prefixMode === PrefixModes.COMMAND) {
                        panel.plasmoidBridge.runCommand(panel.prefixArgument, cfg.terminalShell)
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
                        if (categoryGridView.currentIndex < 0) {
                            categoryGridView.contentY = 0
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
                commandRunner: panel.plasmoidBridge
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
            onFavoritesToggled: function(active) {
                // Update model state BEFORE UI state so bindings see the
                // correct proxy data when showCategoryGrid re-evaluates. Leaving
                // favourites is always paired with a categorySelected (All or a
                // category), so the scroll/reset of the sections grid happens once
                // there — no resetView here, which would scroll to the top first.
                if (panel.appsModel) {
                    panel.appsModel.showFavoritesOnly = active
                    panel.appsModel.filterCategory = ""
                }
                categoryBar.favoritesActive = active
                searchBar.field.forceActiveFocus()
            }
            // The bar tracks the selection (categoryBar.selectedCategory); the view
            // reacts to it here — one feature across all sorts: folders root the
            // tree, By Category scrolls to the section, flat sorts filter the grid.
            onCategorySelected: function(name) {
                searchBar.field.forceActiveFocus()
                if (panel.categoryFolders) {
                    const menuModel = panel.plasmoidBridge ? panel.plasmoidBridge.menuTreeModel : null
                    if (menuModel)
                        menuModel.setRootPath(name !== "" && panel.appsModel
                                              ? panel.appsModel.categoryMenuPath(name) : "")
                    if (panel.appsModel)
                        panel.appsModel.filterCategory = ""
                } else if (panel.isSortByCategory) {
                    // Sections: scroll to the category, never filter (the grid shows
                    // every section).
                    if (panel.appsModel)
                        panel.appsModel.filterCategory = ""
                    if (name !== "")
                        Qt.callLater(function() { categoryGridView.scrollToCategory(name) })
                    else
                        categoryGridView.resetView()
                } else if (panel.appsModel) {
                    // Flat sort: filter the grid to the selected category.
                    panel.appsModel.filterCategory = name
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
                listDirectory: panel.plasmoidBridge.listDirectory
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
            model: panel.isSearching ? panel.searchModel : null
            iconSize: panel.gridIconSize
            fontScale: panel.densityScale
            showDividers: panel.cfgShowDividers
            shadowEnabled: cfg.iconShadow
            showShortcuts: cfg.showSearchShortcuts
            animateHighlight: cfg.hoverAnimation > 0
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
                // runnerResultFavoriteId maps via the runner submodel, so it takes
                // the runner-row index (unified row minus the app count), the same
                // sourceIndex showForRunner uses — not the raw unified index.
                var favoriteId = panel.plasmoidBridge.runnerResultFavoriteId(item.sourceIndex)
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
            groupedApps: panel.showCategoryGrid && panel.appsModel
                ? panel.appsModel.groupedByCategory : []
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
                                       categoryGridView.selectedSidList())
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
            onFolderContextRequested: function(menuPath) { menuFolderContextMenu.openFor(menuPath) }
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
                model: panel.isSearching ? null : panel.gridModel
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
                    contextMenu.showForApp(storageId, desktopFile,
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
    }


    LauncherActions {
        id: launcherActions
        actions: panel.plasmoidBridge
    }

    // Right-click menu for a menu-tree folder (#201): edit it in kmenuedit, the
    // same action the category bar offers per category.
    AppGridMenu {
        id: menuFolderContextMenu
        property string menuPath: ""
        function openFor(path) {
            menuFolderContextMenu.menuPath = path
            menuFolderContextMenu.popup()
        }
        AppGridMenuItem {
            text: i18nd("dev.xarbit.appgrid", "Edit in Menu Editor…")
            icon.name: "kmenuedit"
            onClicked: launcherActions.editMenuItem(menuFolderContextMenu.menuPath)
        }
    }

    SessionActions { id: sessionActions }

    SearchSessionManager {
        id: searchSession
        appsModel: panel.appsModel
        categoryBar: categoryBar
        searchAll: cfg.searchAll
        isPrefixMode: panel.isPrefixMode
    }

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
        onRenameFolderRequested: folderId => renameFolderDialog.openFor(folderId)
        onLaunchFolderRequested: folderId => panel.launchFolder(folderId)

        // Wrap the bridge's C++ methods in closures (not bare refs): called as
        // contextMenu.<prop>() the bare ref would run with the menu as `this`, not
        // the bridge — Qt6 warns about that (NativeMethodBehavior). The arrow binds
        // the call back to plasmoidBridge.
        appActions: sid => panel.plasmoidBridge.appActions(sid)
        launchAppAction: (sid, idx) => panel.plasmoidBridge.launchAppAction(sid, idx)
        canManageInDiscover: sid => panel.plasmoidBridge.canManageInDiscover(sid)
        openInDiscover: sid => panel.plasmoidBridge.openInDiscover(sid)
        pinToTaskManager: launcherActions.pinToTaskManager
        addToDesktop: launcherActions.addToDesktop
        canPinToTaskManager: launcherActions.canPinToTaskManager
        canAddToDesktop: launcherActions.canAddToDesktop
        editApplication: launcherActions.editMenuItem
        runRunnerAction: function(rowIdx, actIdx) {
            if (panel.plasmoidBridge.runRunnerAction(rowIdx, actIdx))
                closeRequested()
        }

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
        onClearSelectionRequested: {
            const v = panel.activeMultiSelectView
            if (v) v.clearSelection()
        }
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
        onAccepted: launcher.runBulkLaunch(pendingSids)
    }

    // Folder "Launch All" confirm — like bulkLaunchDialog but launches each
    // member favourite-aware (handles KCMs) via _launchFolderMembers (#18).
    Kirigami.PromptDialog {
        id: folderLaunchDialog
        property var pendingMembers: []
        title: i18nd("dev.xarbit.appgrid", "Launch all in folder?")
        subtitle: i18ndp("dev.xarbit.appgrid",
            "Open %1 application at once?",
            "Open %1 applications at once?",
            pendingMembers.length)
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel
        onAccepted: panel._launchFolderMembers(pendingMembers)
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
        onAccepted: launcher.runBulkHide(pendingSids)
    }

    // Folder rename (#18).
    Kirigami.PromptDialog {
        id: renameFolderDialog
        property string folderId: ""
        title: i18nd("dev.xarbit.appgrid", "Rename Folder")
        standardButtons: Kirigami.Dialog.Ok | Kirigami.Dialog.Cancel

        function openFor(fid) {
            folderId = fid
            nameField.text = panel.favoritesGroupedModel
                ? panel.favoritesGroupedModel.folderName(fid) : ""
            open()
            nameField.forceActiveFocus()
            nameField.selectAll()
        }
        onAccepted: {
            const name = nameField.text.trim()
            if (panel.favoritesGroupedModel && folderId.length > 0 && name.length > 0)
                panel.favoritesGroupedModel.renameFolder(folderId, name)
        }

        PlasmaComponents.TextField {
            id: nameField
            onAccepted: renameFolderDialog.accept()
        }
    }
}
