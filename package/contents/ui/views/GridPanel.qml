/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable grid panel content. Always hosted inside a Plasma surface that
    draws its own themed background, blur and shadow: a native Plasma popup
    (Panel variant) or the standalone daemon's PlasmaWindow. The panel itself
    is therefore transparent and chromeless.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../widgets"
import "../js/favoriteid.js" as FavoriteId
import "../js/migrations.js" as Migrations
import "../js/searchresultnav.js" as SearchResultNav
import "../js/constants.js" as Const
import "../js/gridmetrics.js" as GridMetrics
import "../js/prefixmodes.js" as PrefixModes
import "../js/scale.js" as Scale

Kirigami.ShadowedRectangle {
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
    // for the launch-bookkeeping flush (recents / launchCounts / knownApps /
    // hiddenApps / favoritesPortedToKAstats / iconMigratedFrom17).
    required property var configuration

    // Single Plasmoid-callback surface; see PlasmoidBridge.qml. Tests
    // inject a plain QtObject stub with the same method names.
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
        nativePopup: true
        sizeToContent: panel.sizeToContent
        hideGridWhenEmpty: panel.effectiveHideGridWhenEmpty
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
        const q = searchBar.text
        if (q.length === 0)
            return ""
        const word = panel.appsModel.completionFor(q)
        return word.length > q.length ? word.substring(q.length) : ""
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

    // The daemon hosts the panel in a fixed-size PlasmaWindow it sizes from the
    // panel's implicitHeight, so the panel must report the compact-aware
    // effectiveHeight (like the old center GridWindow). The panel-plasmoid variant
    // leaves this off: it seeds panelHeight then lets Plasma own the popup size.
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
    readonly property real headerHeight: Kirigami.Units.gridUnit * 5
    readonly property real panelWidth: estCellWidth * columns + panelMargin * 2
    readonly property real panelHeight: estCellHeight * rows + panelMargin * 2 + headerHeight
    // Compact mode height — snug fit around the header row (search +
    // power buttons), no slack for a category bar or grid below.
    readonly property real compactHeight: headerRow.implicitHeight + panelMargin * 2
    readonly property real effectiveHeight: _emptyHiddenState ? compactHeight : panelHeight

    // Only seed the *initial* popup size via implicitWidth/Height and leave
    // width/height + preferred size unbound, so Plasma's own popup-resize
    // persistence owns it. A hard preferred-size binding re-asserted the estimate
    // on every layout pass (e.g. a monitor wake) and snapped the user's edge-drag
    // back, shrinking the popup (#146).
    implicitWidth: panelWidth
    // sizeToContent (daemon): track the compact-aware effectiveHeight so the
    // hosting PlasmaWindow shrinks for compact mode and grows when the grid
    // reveals. Plain popup (panel variant): seed panelHeight only.
    implicitHeight: sizeToContent ? effectiveHeight : panelHeight

    Layout.preferredWidth: -1
    Layout.preferredHeight: -1
    Layout.minimumWidth: Kirigami.Units.gridUnit * 12
    Layout.minimumHeight: Kirigami.Units.gridUnit * 12
    // The launcher always renders inside a Plasma popup / PlasmaWindow, which draws
    // the themed background, blur, contrast and shadow itself (the theme owns the
    // corner), so the panel rect is transparent, chromeless and square.
    radius: 0

    color: "transparent"
    border.width: 0
    shadow.size: 0

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
    // config. (Launch state — hidden/recent/known/counts — is synced separately
    // by AppGridController via the shared LaunchStateStore.)
    ModelConfigSync {
        id: modelSync
        appsModel: panel.appsModel
        cfg: cfg
    }
    function syncModelFromConfig() { modelSync.sync() }

    Component.onCompleted: {
        const _t0 = Date.now()
        Migrations.migratePowerButtons(panel.configuration)
        Migrations.migrateHeaderActions(panel.configuration)
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
        favoritesPortedToKAstats: cfg.favoritesPortedToKAstats
        legacyFavorites: cfg.favoriteApps
        markPorted: function() { panel.configuration.favoritesPortedToKAstats = true }
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
    // Folder currently open (empty = none); the open-mode host watches this.
    property string openFolderId: ""
    // Bumped when the grouped model reconciles, so an open folder re-reads its
    // live name/members; closes the overlay if the folder is gone (ungrouped).
    property int _foldersRevision: 0
    Connections {
        target: panel.favoritesGroupedModel
        ignoreUnknownSignals: true
        function onFoldersChanged() {
            panel._foldersRevision++
            if (panel.openFolderId.length > 0
                    && panel.favoritesGroupedModel.folderMembers(panel.openFolderId).length === 0)
                panel.openFolderId = ""
        }
        function onLayoutChanged() { panel._foldersRevision++ }
        // Prompt for a name as soon as a folder is created (drag-fold, menu, empty).
        function onFolderCreated(folderId) { renameFolderDialog.openFor(folderId) }
    }
    // Leaving the favourites tab closes any open folder.
    onIsFavoritesActiveChanged: if (!isFavoritesActive) openFolderId = ""

    // #193: drop a favorite into the launcher's empty space (anywhere that isn't
    // the favorites grid, but inside the window) to remove it. Lowest z, so the
    // grid's own reorder DropArea catches reorders first; a drop the compositor
    // routes outside the window never reaches here, so it stays put. Acts only on
    // an own drag whose source is actually a favorite — other drops fall through.
    DropArea {
        id: favoriteRemoveArea
        anchors.fill: parent
        z: -10
        enabled: panel.sharedFavoritesModel !== null

        // The dragged sids that are actually favorites (empty unless this is an
        // own drag with at least one favorite source). Drives both the ✕ marker
        // and the drop removal.
        function _favoriteSids(drag) {
            const src = panel.dragSource
            if (!src || !src.isOwnDrag(drag) || !panel.sharedFavoritesModel) {
                return []
            }
            const all = src.sourceStorageIds.length > 0 ? src.sourceStorageIds : [src.sourceStorageId]
            return all.filter(sid => sid && panel.sharedFavoritesModel.isFavorite(FavoriteId.toPrefixed(sid)))
        }

        // The dragged folder's id, if a folder cell is being dragged here (#18).
        function _folderId(drag) {
            const src = panel.dragSource
            return (src && src.isOwnDrag(drag)) ? (src.sourceFolderId || "") : ""
        }

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
            }
        }
        onPositionChanged: drag => {
            if (favoriteRemoveArea._removable(drag))
                drag.accept(Qt.MoveAction)
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
        categoryBar.resetScroll()
        _resetSearchSession()
        // Don't reopen the last folder on the next launch (#18).
        openFolderId = ""
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

        // Clear any stale Alt-held state: the panel popup item is reused
        // across open/close, so a missed Alt key-release (focus left the
        // window, or it was closed mid-Alt) would otherwise leave the
        // category mnemonics underlined on the next open (#168).
        categoryBar.altHeld = false

        // Restore starting tab
        var startFav = cfgShowCategoryBar && cfgStartWithFavorites
        categoryBar.favoritesActive = startFav
        categoryBar.scrollOnlySelected = ""

        // Sync model from config and reset filter state. Default apps are no
        // longer re-resolved here (#200): AppFilterModel refreshes them on
        // KSycoca / kdeglobals change, so the open path stays cheap.
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
        categoryGridView.resetView()
        _needsScrollToTop = true
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

        // -- Category bar --
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
            editCategoryInMenu: launcherActions.editMenuItem
            favoritesFirst: panel.cfgStartWithFavorites
            isSortByCategory: panel.isSortByCategory
            fontScale: panel.densityScale
            displayMode: cfg.categoryBarDisplay
            scrollOnlyMode: panel.showCategoryGrid
            hideEmptyCategories: cfg.hideEmptyCategories
            openOnHover: cfg.openCategoryOnHover
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
                        categoryGridView.resetView()
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
                        categoryGridView.resetView()
                    }
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
            active: panel.isPrefixMode
            visible: active
            sourceComponent: PrefixModeView {
                mode: panel.prefixMode
                argument: panel.prefixArgument
                searchField: searchBar.field
                sharedFavoritesModel: panel.sharedFavoritesModel
                showScrollbars: cfg.showScrollbars
                appsModel: panel.appsModel
                listDirectory: panel.plasmoidBridge.listDirectory
                sysInfoProvider: panel.sysInfoProvider
                updateChecker: panel.updateChecker
                favoritesPortedToKAstats: cfg.favoritesPortedToKAstats
                favoriteApps: cfg.favoriteApps
                markUnported: function() { panel.configuration.favoritesPortedToKAstats = false }
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

        // -- Unified search results --
        SearchResultsList {
            id: searchResultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
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
                var favoriteId = panel.plasmoidBridge.runnerResultFavoriteId(index)
                contextMenu.showForRunner(item.sourceIndex, actions, favoriteId)
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
            onBulkLaunchRequested: function(sids) { panel._requestBulkLaunch(sids) }
            onContextMenuRequested: function(proxyIndex, storageId, desktopFile) {
                contextMenu.showForApp(storageId, desktopFile,
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
                model: panel.isSearching ? null : panel.gridModel
                appsModel: panel.appsModel
                sharedFavoritesModel: panel.sharedFavoritesModel
                favoritesGroupedModel: panel.favoritesGroupedModel
                onOpenFolderRequested: folderId => panel.openFolderId = folderId
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

            // The folder popup overlays the grid. _foldersRevision re-reads the
            // live name/members when the model reconciles while it's open (#18).
            Loader {
                anchors.fill: parent
                z: 20
                active: panel.openFolderId.length > 0 && panel.favoritesGroupedModel
                sourceComponent: FolderOpenHost {
                    readonly property int _rev: panel._foldersRevision
                    folderName: panel.favoritesGroupedModel.folderName(panel.openFolderId)
                    members: { _rev; return panel.favoritesGroupedModel.folderMembers(panel.openFolderId) }
                    appsModel: panel.appsModel
                    sharedFavoritesModel: panel.sharedFavoritesModel
                    favoriteIdRole: panel.favoriteIdRole
                    dragSource: panel.dragSource
                    columns: appGrid.effectiveColumns
                    cellWidth: appGrid.cellWidth
                    cellHeight: appGrid.cellHeight
                    iconSize: panel.gridIconSize
                    fontScale: panel.densityScale
                    shadowEnabled: cfg.iconShadow
                    reduceGridSpacing: cfg.reduceGridSpacing
                    hoverAnimation: cfg.hoverAnimation
                    hoverHighlight: cfg.hoverHighlight
                    Component.onCompleted: forceActiveFocus()
                    onCloseRequested: panel.openFolderId = ""
                    onMemberRemoveRequested: sid => {
                        if (panel.favoritesGroupedModel)
                            panel.favoritesGroupedModel.removeFromFolder(panel.openFolderId, sid)
                    }
                    onMemberReorderRequested: (from, to) => {
                        if (panel.favoritesGroupedModel)
                            panel.favoritesGroupedModel.reorderInFolder(panel.openFolderId, from, to)
                    }
                    onMemberContextRequested: (sid, df) => contextMenu.showForApp(sid, df, [])
                    onMemberLaunched: sid => {
                        panel.openFolderId = ""
                        // launchFavorite handles both apps and KCMs (which need
                        // KAStats trigger, not the app launcher); then close.
                        appGrid.launchFavorite(sid)
                        panel.closeRequested()
                    }
                }
            }

        }
    }


    // -----------------------------------------------------------------------
    // Context menu
    // -----------------------------------------------------------------------

    LauncherActions {
        id: launcherActions
        actions: panel.plasmoidBridge
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
        favoritesActive: panel.isFavoritesActive
        appletInterface: panel.appletInterface
        onOpenFolderRequested: folderId => panel.openFolderId = folderId
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
