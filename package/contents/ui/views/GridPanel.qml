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
import dev.xarbit.appgrid.models

import "../controllers"
import "../widgets"
import "../js/constants.js" as Const
import "../js/gridmetrics.js" as GridMetrics
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
        appGridPane.grid.shakeAllIcons()
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
    // ConfigCache (`config`) below; writes still target this handle directly
    // for the launch-bookkeeping flush (recents / launchCounts /
    // hiddenApps).
    required property var configuration

    // Supplied by the plasmoid root, forwarded to the prefix views (`i:`). A
    // function returning the system-info map, not the map itself, so the
    // /proc + os-release reads only run when the i: info view opens (#200).
    required property var sysInfoProvider

    // -- Configuration (single source of truth for all config reads) --
    ConfigCache { id: config; source: panel.configuration }

    // One-shot override set by the secondary "Open in Compact Mode" global
    // shortcut. While true, the panel behaves as if hideGridWhenEmpty were
    // enabled, regardless of the persisted config. Reset on close so the
    // next normal open uses the user's chosen mode.
    property bool forceCompact: false
    readonly property bool effectiveHideGridWhenEmpty: config.hideGridWhenEmpty || forceCompact

    // -- Sort helpers --
    readonly property bool isSortByCategory: config.sortMode === AppFilterModel.ByCategory

    // -- View state --
    // Which views show is VisibilityState's (`visibility`), compact mode
    // included: it hides the grid and category chrome until the user types,
    // or pops the grid open (gridRevealed) with Down or the wheel.
    readonly property bool isSearching: searchBar.text.length > 0
    // The views switch between grid and search list on the search the model
    // has actually been filtered with, not the live field text: the filter
    // pass is deferred (see SearchPipeline), and switching early showed the
    // search list on the unfiltered apps, or rebuilt the grid from the stale
    // search results before the restored filter landed.
    readonly property bool _searchApplied: current.searchText.length > 0
    readonly property bool isFavoritesActive: current.favorites

    // The selected tab and the applied search; the apps model's filter
    // follows from them (see ViewState).
    ViewState {
        id: current
        appsModel: panel.appsModel
        searchAll: config.searchAll
        isPrefixMode: panel.isPrefixMode
        categoryFilters: !panel.categoryFolders && !panel.isSortByCategory
    }

    VisibilityState {
        id: visibility
        sizeToContent: panel.sizeToContent
        hideGridWhenEmpty: panel.effectiveHideGridWhenEmpty
        showCategoryBar: config.showCategoryBar
        isSearching: panel._searchApplied
        isPrefixMode: panel.isPrefixMode
        isFavoritesActive: panel.isFavoritesActive
        isSortByCategory: panel.isSortByCategory
        categoryFolders: panel.categoryFolders
        // A specific category tab is selected → fold that category in any sort.
        categoryFiltered: current.category.length > 0
    }

    // Folder tree needs the kmenuedit hierarchy, which only exists in system
    // categories mode (#201).
    readonly property bool categoryFolders: config.useSystemCategories && config.categoryFoldersEnabled

    readonly property alias showAppGrid: visibility.appGridVisible

    // True while the menu folder view is inside a sub-folder — the variants' Esc
    // Shortcut yields to it so Esc climbs out a level instead of closing (#201),
    // just like favFolderOpen does for a favourites folder.
    readonly property bool menuFolderCanGoBack: visibility.menuFolderVisible && menuFolderView.canGoBack
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
        if (!config.searchInlineCompletion || !showSearchResults || panel.isPrefixMode || !panel.appsModel)
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
        viewState: current
        runnerSourceModel: panel.runnerSourceModel
        useExtraRunners: config.useExtraRunners
        isPrefixMode: panel.isPrefixMode
    }

    // Whichever grid view currently owns a SelectionState — used to route
    // menu-driven selection toggles. Search and prefix views resolve to
    // null because they don't host multi-select; callers treat that as a
    // silent no-op.
    readonly property var activeMultiSelectView: showAppGrid ? appGridPane.grid
                                              : visibility.categorySectionsVisible ? categoryGridView
                                              : null
    // The view the keyboard reaches from the search field (Down, Tab, Enter),
    // or null while searching. Each has enterFromSearch() and activateCurrent().
    readonly property var activeKeyView: showAppGrid ? appGridPane.grid
                                       : visibility.categorySectionsVisible ? categoryGridView
                                       : visibility.menuFolderVisible ? menuFolderView
                                       : null

    // -- Icon size mapping (0=Small/medium, 1=Medium/large, 2=Large/huge) --
    readonly property real gridIconSize: {
        var preset = config.iconSize
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
    readonly property real densityScale: Scale.textScale(config.iconSize, config.independentTextSize)

    // What every grid reads from the panel, and where its requests go.
    GridHost {
        id: gridHost
        appsModel: panel.appsModel
        favoritesManager: favorites
        dragSource: panel.dragSource
        searchField: searchBar.field
        cellStyle: look
        columns: config.gridColumns
        onLaunchAppRequested: index => launcher.launchApp(index)
        onLaunchRequested: storageId => launcher.launchAppByStorageId(storageId)
        onBulkLaunchRequested: sids => launcher.requestBulkLaunch(sids)
        onCategoryNavRequested: direction => panel.navigateCategory(direction)
        onAppMenuRequested: (storageId, desktopFile, selectedSids) =>
            menus.showForApp(storageId, desktopFile, selectedSids)
    }

    // How every view draws its cells and rows, from the settings.
    CellStyle {
        id: look
        iconSize: panel.gridIconSize
        fontScale: panel.densityScale
        hoverAnimation: config.hoverAnimation
        shadowEnabled: config.iconShadow
        hoverHighlight: config.hoverHighlight
        showTooltips: config.showTooltips
        showNewAppBadge: config.showNewAppBadge
        showDividers: config.showDividers
        reduceGridSpacing: config.reduceGridSpacing
        showScrollbars: config.showScrollbars
    }

    // The keys pressed in the search field, to the results, the shown grid
    // or the prefix mode's view.
    SearchKeyRouter {
        id: searchKeys
        results: searchResultsList
        keyView: panel.activeKeyView
        prefixView: prefixModeLoader.item
        prefixMode: panel.prefixMode
        resultsShown: panel.showSearchResults
        searching: panel.isSearching
        collapsible: config.hideGridWhenEmpty
        collapsed: visibility.emptyHidden
        revealed: visibility.gridRevealed
        onLaunchResultRequested: index => launcher.launchSearchResult(index)
        onRunRequested: function(inTerminal) {
            const system = panel.plasmoidBridge.systemActions
            if (inTerminal)
                system.runInTerminal(panel.prefixArgument, config.terminalShell)
            else
                system.runCommand(panel.prefixArgument, config.terminalShell)
            panel.closeRequested()
        }
        onRevealRequested: revealed => visibility.gridRevealed = revealed
    }

    // -- Prefix mode detection --
    PrefixDetector { id: prefixDetector; input: searchBar.text }
    readonly property string prefixMode: prefixDetector.mode
    readonly property bool isPrefixMode: prefixDetector.isPrefixMode
    readonly property string prefixArgument: prefixDetector.argument

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
                                         densityScale, config.reduceGridSpacing)
    readonly property real estCellHeight: GridMetrics.labelledCellHeight(gridIconSize,
                                          Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, densityScale)

    readonly property real panelMargin: Kirigami.Units.largeSpacing
    readonly property real panelWidth: estCellWidth * config.gridColumns + panelMargin * 2
    // Each full-height body view carries this as Layout.preferredHeight, so the
    // panel sizes to header(natural) + rows*cell — visible-rows honoured whatever
    // header chrome shows (#205).
    readonly property real bodyHeight: estCellHeight * config.gridRows

    // Full (grid-shown) height — used only to position the daemon window so a
    // start-compact reveal grows downward without drift. Real header items, no
    // units estimate.
    readonly property real panelHeight: panelMargin * 2 + headerRow.implicitHeight
        + Kirigami.Units.largeSpacing + bodyHeight
        + (visibility.catBarVisible ? categoryBar.implicitHeight + Kirigami.Units.largeSpacing * 3 : 0)

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
        enabled: config.hideGridWhenEmpty && !panel.isSearching
                 && searchBar.field.activeFocus
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            visibility.gridRevealed = event.angleDelta.y < 0
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
        cfg: config
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

    // Favourites folders (issue #18). The C++ grouped model (shared by both
    // variants via the bridge) composes KAStats favourites with the folder layout.
    // One model owns the favourites tab (alpha-sort off): the grouped model in
    // both grouping states. Its groupingEnabled flag (bound below from
    // favoriteFoldersEnabled) folds folders into tiles or expands them inline, so
    // toggling grouping keeps a single layout and order (issue #200).
    readonly property var favoritesGroupedModel: panel.plasmoidBridge
        ? panel.plasmoidBridge.favoritesGroupedModel : null
    readonly property bool useFavoritesGrouped: favoritesGroupedModel && !config.sortFavoritesAlphabetically
    Binding {
        target: panel.favoritesGroupedModel
        property: "groupingEnabled"
        value: config.favoriteFoldersEnabled
        when: panel.favoritesGroupedModel
        restoreMode: Binding.RestoreNone
    }
    // The model that drives the main grid: the grouped favourites model on the
    // favourites tab, else the filtered app model (All / categories / alpha-sorted
    // favourites).
    readonly property var gridModel: !isFavoritesActive ? appsModel
        : (useFavoritesGrouped ? favoritesGroupedModel : appsModel)
    // Inside a favourites folder (#18): feeds the variants' Escape Shortcut,
    // which yields so Esc climbs out of the folder.
    readonly property bool favFolderOpen: appGridPane.folderOpen
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
        enabled: favorites.sharedFavoritesModel !== null && panel.isFavoritesActive
        dragSource: panel.dragSource
        favoritesManager: favorites
    }

    // Back to the just-opened state on every show or hide: no menu open, the
    // search input empty (SearchBar.onTextChanged propagates the empty string
    // into appsModel and runnerSourceModel) and the compact grid collapsed.
    function _resetSession() {
        menus.close()
        categoryBar.closeCategoryMenu()
        headerActions.closeMenus()
        searchBar.text = ""
        visibility.gridRevealed = false
    }

    // Done on close (not open) so the height/scroll transitions back to
    // the compact-mode starting state are invisible behind the fade-out
    // instead of flashing on the next open.
    function resetOnClose() {
        _resetSession()
        categoryBar.resetScroll()
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
        current.reset(config.showCategoryBar && config.startWithFavorites)
    }

    // Pure UI-state reset (scroll, selection, category view). Close-only: running
    // it on open would visibly jump the grid as the popup appears.
    function _resetGridUiState() {
        categoryBar.altHeld = false
        appGridPane.reset()
        searchResultsList.resetView()
        categoryGridView.resetView()
        menuFolderView.reset()
    }

    // Perf instrumentation for the open path (#200). console.debug is silent
    // unless QML debug logging is on: QT_LOGGING_RULES="qml.debug=true".
    function _perfMark(label, since) { console.debug("[appgrid.perf]", label, (Date.now() - since), "ms") }

    // -- Reset state (called when showing the grid) --
    function resetState() {
        const _t0 = Date.now()
        _resetSession()

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

    // Launch routing (single + bulk, the bulk confirm threshold) lives in the
    // coordinator; the panel keeps the UI side effects it signals — the
    // search-field paste and the confirm dialog.
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
    // For tests: the launch routing as the panel wired it.
    readonly property alias launchCoordinator: launcher

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
                onAltNumberPressed: number => searchKeys.altNumber(number)
                onAccepted: searchKeys.accept()
                onMoveDown: searchKeys.moveDown()
                onMoveUp: searchKeys.moveUp()
                onTabPressed: searchKeys.tab()
                onPageUp: searchKeys.pageUp()
                onPageDown: searchKeys.pageDown()
                onHome: searchKeys.home()
                onEnd: searchKeys.end()
            }

            HeaderActions {
                id: headerActions
                Layout.alignment: Qt.AlignVCenter
                isSearching: panel.isSearching
                showSearchResults: panel.showSearchResults
                currentResultIcon: panel.currentResultIcon
                densityScale: panel.densityScale
                showActionLabels: config.showActionLabels
                hideMenuButtonLabel: config.hideMenuButtonLabel
                headerActions: config.headerActions
                customHeaderActions: config.customHeaderActions
                commandRunner: panel.plasmoidBridge ? panel.plasmoidBridge.systemActions : null
                terminalShell: config.terminalShell
                menuButtonIcon: config.menuButtonIcon
                iconShadow: config.iconShadow
                updateChecker: panel.updateChecker
                sessionActions: session
                onActionTriggered: panel.closeRequested()
                onConfigureRequested: panel.configureRequested()
            }
        }

        HorizontalDivider {
            Layout.fillWidth: true
            visible: visibility.catBarVisible
            opacity: look.showDividers ? 1 : 0
        }

        CategoryBar {
            id: categoryBar
            visible: visibility.catBarVisible
            Layout.leftMargin: Kirigami.Units.smallSpacing
            appsModel: panel.appsModel
            isFavorite: sid => favorites.isFavorite(sid)
            editCategoryInMenu: actions.editMenuItem
            favoritesFirst: config.startWithFavorites
            isSortByCategory: panel.isSortByCategory
            fontScale: panel.densityScale
            displayMode: config.categoryBarDisplay
            hideEmptyCategories: config.hideEmptyCategories
            openOnHover: config.openCategoryOnHover
            // The bar shows the view state and asks to change it. Leaving
            // favourites goes through categorySelected (All or a category), so
            // the scroll/reset of the sections grid happens once there.
            favoritesActive: current.favorites
            selectedCategory: current.category
            onFavoritesToggled: function(active) {
                current.selectFavorites(active)
                searchBar.field.forceActiveFocus()
            }
            // One feature across all sorts: flat sorts filter the grid (the view
            // state does that), folders root the tree, By Category scrolls to the
            // section.
            onCategorySelected: function(name) {
                current.selectCategory(name)
                searchBar.field.forceActiveFocus()
                const view = panel.categoryFolders ? menuFolderView
                           : panel.isSortByCategory ? categoryGridView : null
                if (view)
                    view.showCategory(name)
            }
        }

        HorizontalDivider {
            Layout.fillWidth: true
            visible: visibility.catBarVisible
            opacity: look.showDividers ? 1 : 0
        }

        AnswerToEverything {
            queryText: searchBar.text
            resultsActive: panel.showSearchResults && !panel.isPrefixMode
            iconSize: panel.gridIconSize
        }

        // The body: one view at a time fills it (a prefix mode's, the search
        // results or a grid), and it sizes the panel to the visible rows (#205).
        // Hidden when none shows, so the compact panel collapses to the header.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: panel.bodyHeight
            visible: visibility.bodyVisible

            // -- Prefix mode view --
            // Built only when the user actually enters a prefix mode (#200). The
            // five sub-views (file browser, terminal, info, help, hidden) are rare,
            // so instantiating them eagerly only weighed down cold open.
            Loader {
                id: prefixModeLoader
                anchors.fill: parent
                active: panel.isPrefixMode
                visible: active
                sourceComponent: PrefixModeView {
                    mode: panel.prefixMode
                    argument: panel.prefixArgument
                    searchField: searchBar.field
                    showScrollbars: look.showScrollbars
                    launchState: panel.plasmoidBridge ? panel.plasmoidBridge.launchState : null
                    listDirectory: path => panel.plasmoidBridge.systemActions.listDirectory(path)
                    sysInfoProvider: panel.sysInfoProvider
                    updateChecker: panel.updateChecker
                    onFileOpened: panel.closeRequested()
                    onDirectoryNavigated: function(path) {
                        searchBar.text = path
                    }
                }
            }

            SearchResultsList {
                id: searchResultsList
                anchors.fill: parent
                visible: panel.showSearchResults
                model: panel._searchApplied ? panel.searchModel : null
                cellStyle: look
                showShortcuts: config.showSearchShortcuts
                searchField: searchBar.field
                favoritesManager: favorites
                plasmoidBridge: panel.plasmoidBridge
                onLaunched: index => launcher.launchSearchResult(index)
                onContextMenuRequested: function(index, storageId, desktopFile) {
                    // search-results has no multi-select; passing canSelect=false
                    // hides the otherwise-no-op "Add to Selection" item.
                    if (storageId)
                        menus.showForApp(storageId, desktopFile, [], false)
                }
                onRunnerContextMenuRequested: index => menus.showForRunnerResult(index)
            }

            // Flat category sections (the By Category sort).
            CategoryGridView {
                id: categoryGridView
                anchors.fill: parent
                visible: visibility.categorySectionsVisible
                host: gridHost
                rowsModel: panel.plasmoidBridge ? panel.plasmoidBridge.categoryRowsModel : null
                showRecents: config.showRecentApps
                             && panel.appsModel
                             && panel.appsModel.recentApps.length > 0
                             && !panel.isFavoritesActive
                             && !config.startWithFavorites
            }

            // -- Menu folder tree (By Category + group into folders, #201) --
            MenuFolderView {
                id: menuFolderView
                anchors.fill: parent
                visible: visibility.menuFolderVisible
                // Gated on the feature so the (lazy) menu tree is never built when
                // folders are off — reading menuTreeModel is what triggers the walk.
                menuModel: panel.categoryFolders && panel.plasmoidBridge ? panel.plasmoidBridge.menuTreeModel : null
                host: gridHost
                hideEmpty: config.hideEmptyCategories
                onFolderContextRequested: function(menuPath) { menus.showForMenuFolder(menuPath) }
            }

            // -- App grid (favourites / all / category) --
            AppGridPane {
                id: appGridPane
                anchors.fill: parent
                visible: panel.showAppGrid
                cfg: config
                host: gridHost
                model: panel._searchApplied ? null : panel.gridModel
                favoritesActive: panel.isFavoritesActive
                onFolderContextMenuRequested: folderId => menus.showForFolder(folderId)
                onEmptyAreaContextMenuRequested: menus.showForEmptyArea()
            }
        }
    }


    LauncherActions {
        id: actions
        taskManager: panel.plasmoidBridge ? panel.plasmoidBridge.plasmoidClient : null
        desktop: panel.plasmoidBridge ? panel.plasmoidBridge.systemActions : null
    }

    SessionActions { id: session }

    PanelMenus {
        id: menus
        plasmoidBridge: panel.plasmoidBridge
        cfg: config
        launcherActions: actions
        appsModel: panel.appsModel
        searchModel: panel.searchModel
        favoritesManager: favorites
        appletInterface: panel.appletInterface
        favoritesActive: panel.isFavoritesActive
        selectionView: panel.activeMultiSelectView
        onBulkLaunchRequested: (sids, fromFolder) => launcher.requestBulkLaunch(sids, fromFolder)
        onBulkHideRequested: sids => dialogs.confirmBulkHide(sids)
        onRenameFolderRequested: folderId => dialogs.renameFolder(folderId)
        onCloseRequested: panel.closeRequested()
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
