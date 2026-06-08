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
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents

import "../controllers"
import "../widgets"
import "../js/launchcounts.js" as LaunchCounts
import "../js/migrations.js" as Migrations
import "../js/searchresultnav.js" as SearchResultNav
import "../js/themecolors.js" as ThemeColors
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

    // System-info snapshot supplied by the plasmoid root, forwarded to
    // the prefix views (i.e. `i:`).
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

    // One-shot override set by the secondary "Open in Compact Mode" global
    // shortcut. While true, the panel behaves as if hideGridWhenEmpty were
    // enabled, regardless of the persisted config. Reset on close so the
    // next normal open uses the user's chosen mode.
    property bool forceCompact: false
    readonly property bool effectiveHideGridWhenEmpty: cfgHideGridWhenEmpty || forceCompact

    // Usable size of the host (the centred window's surface), the cap the panel
    // must not exceed. The owning GridWindow injects its own width/height — the
    // compositor-validated LayerShell surface — which stays correct across a
    // resume; Qt's Screen attached property can transiently report a bogus
    // placeholder when outputs drop on wake, shrinking/mis-sizing the panel.
    // Defaults to Screen for standalone/test use.
    property real availableWidth: Screen.width
    property real availableHeight: Screen.height

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

    // When used as a native Plasma popup, skip custom chrome (Plasma provides its own)
    property bool nativePopup: false

    // Icon-based estimate avoids the circular dependency panel width →
    // grid cellWidth → grid width → panel width. estCellHeight must match
    // AppGridView.cellHeight with labels visible (gridUnit too small per
    // row would accumulate and clip the bottom row).
    readonly property real estCellWidth: GridMetrics.labelledCellWidth(gridIconSize,
                                         Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, densityScale)
    readonly property real estCellHeight: GridMetrics.labelledCellHeight(gridIconSize,
                                          Kirigami.Units.gridUnit, Kirigami.Units.smallSpacing, densityScale)

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
    readonly property real compactShift: effectiveHideGridWhenEmpty
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
        value: Math.min(panel.panelWidth, panel.availableWidth * 0.9)
    }
    Binding on height {
        when: !panel.nativePopup
        value: Math.min(panel.effectiveHeight, panel.availableHeight * 0.9)
    }

    // Set by on_EmptyHiddenStateChanged to skip the next height Behavior
    // animation. See the comment on that handler for the full rationale.
    property bool _snapHeight: false

    Behavior on height {
        enabled: !panel.nativePopup && effectiveHideGridWhenEmpty && !panel._snapHeight
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.OutCubic
        }
    }

    Layout.preferredWidth: nativePopup ? -1 : width
    Layout.preferredHeight: nativePopup ? -1 : height
    Layout.minimumWidth: nativePopup ? Kirigami.Units.gridUnit * 12 : width
    Layout.minimumHeight: nativePopup ? Kirigami.Units.gridUnit * 12 : height
    readonly property int requestedRadius: cfg.overrideRadius ? cfg.cornerRadius
                                                              : Kirigami.Units.cornerRadius
    // Half the smaller dimension is the geometric max for a valid rounded rect.
    // In compact mode the panel collapses to roughly the search bar; a larger
    // radius produces a degenerate shape and gaps in the matching blur region
    // (#151). The blur region reads this same `radius` via GridWindow, so the
    // visible panel and its blur stay consistent at every animated height.
    readonly property int maxValidRadius: Math.floor(Math.min(width, height) / 2)
    // When useThemeChrome is on, the SVG owns the visible corner — use the
    // theme's default so the child clip matches the SVG's drawn curve.
    radius: nativePopup ? 0
        : panel.useThemeChrome ? Math.min(Kirigami.Units.cornerRadius, maxValidRadius)
        : Math.min(requestedRadius, maxValidRadius)

    readonly property real bgOpacity: cfg.effectiveBackgroundOpacity / 100
    // Three rendering paths:
    //   - nativePopup:                 Plasma's popup framework owns the chrome.
    //   - cfg.useThemeBackground:      KSvg.FrameSvgItem below draws the panel face.
    //   - default (solid-color mode):  ShadowedRectangle's own color + border.
    readonly property bool useThemeChrome: !nativePopup && cfg.useThemeBackground

    color: nativePopup || useThemeChrome
        ? "transparent"
        : ThemeColors.tint(Kirigami.Theme.backgroundColor, bgOpacity)

    border.width: useThemeChrome || nativePopup ? 0 : 1
    border.color: useThemeChrome || nativePopup
        ? "transparent"
        : Kirigami.ColorUtils.linearInterpolation(
                Kirigami.Theme.backgroundColor,
                Kirigami.Theme.textColor, 0.2)

    // Layer-shell windows have no WM shadow, so the center variant always
    // paints its own. The dialog SVG used under useThemeChrome would draw
    // its own shadow too in theory, but that one renders inside the SVG's
    // bounding box and gets clipped by GridPanel's edge — invisible. Keep
    // ShadowedRectangle as the single, reliable shadow source for center.
    shadow.size: nativePopup ? 0 : Kirigami.Units.gridUnit
    shadow.color: nativePopup ? "transparent" : Qt.rgba(0, 0, 0, 0.4)
    shadow.xOffset: 0
    shadow.yOffset: nativePopup ? 0 : Kirigami.Units.smallSpacing

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    // Theme-driven panel background. `dialogs/background` is the SVG Plasma
    // themes ship for popup-style surfaces (Kickoff, Plasma dialogs); using
    // it here gives the center variant the same look as the rest of the
    // user's Plasma theme instead of a flat tinted rectangle. Panel variant
    // skips this — Plasma's popup framework renders its own chrome around it.
    KSvg.FrameSvgItem {
        anchors.fill: parent
        imagePath: "dialogs/background"
        visible: panel.useThemeChrome
        opacity: panel.bgOpacity
        z: -1
    }

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
        appsModel.searchShowsHidden = cfg.searchShowsHidden
        appsModel.launchCounts = LaunchCounts.toMap(cfg.launchCounts)
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
            panel.configuration.launchCounts = LaunchCounts.toList(panel.appsModel.launchCounts)
        }
        function onKnownAppsChanged() {
            panel.configuration.knownApps = panel.appsModel.knownApps
        }
        function onHiddenAppsChanged() {
            panel.configuration.hiddenApps = panel.appsModel.hiddenApps
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

        // Clear any stale Alt-held state: the panel popup item is reused
        // across open/close, so a missed Alt key-release (focus left the
        // window, or it was closed mid-Alt) would otherwise leave the
        // category mnemonics underlined on the next open (#168).
        categoryBar.altHeld = false

        // Restore starting tab
        var startFav = cfgShowCategoryBar && cfgStartWithFavorites
        categoryBar.favoritesActive = startFav
        categoryBar.scrollOnlySelected = ""

        // Sync model from config and reset filter state
        syncModelFromConfig()
        if (appsModel) {
            // Re-read the default terminal/browser + mime defaults so a change
            // since the last open boosts the new default while searching.
            appsModel.reloadDefaultApps()
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
    }

    function launchSearchResult(index) {
        var item = panel.searchModel.get(index)
        if (!item) return
        if (item.resultType === "app") {
            launchApp(item.sourceIndex)
            return
        }
        // KRunner UX: calculator hits paste the result back into the
        // search field so the user can keep extending the expression.
        var subst = panel.plasmoidBridge.runnerSubstitutionText(item.sourceIndex)
        if (subst.length > 0) {
            searchBar.field.text = subst
            searchBar.field.cursorPosition = subst.length
            return
        }
        if (panel.plasmoidBridge.runRunnerResult(item.sourceIndex))
            closeRequested()
    }

    // One launch step: KActivities broadcast plus the model launch. Shared
    // by the single-sid path and the bulk path so neither has to repeat
    // the notify/launch pair (notifyAppLaunched is the one-way broadcast
    // that lets other Plasma launchers count AppGrid as a contributing
    // source — we don't read this data back).
    function _launchOneBySid(sid) {
        if (!sid) return
        panel.plasmoidBridge.notifyAppLaunched(sid)
        appsModel.launchByStorageId(sid)
    }

    function launchApp(index) {
        if (!appsModel || index < 0)
            return
        const sid = appsModel.get(index).storageId
        if (sid) panel.plasmoidBridge.notifyAppLaunched(sid)
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
                // Hide the X while the header slot is mid-animation so it
                // doesn't appear to slide in from the right with the
                // growing field; snaps in once the layout settles.
                clearButtonEnabled: !headerSlotAnim.running
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
                    if (panel.prefixMode === PrefixModes.FILES) {
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

            // Right-side header slot. Animates its allocated width
            // between the strip's natural width (idle) and the search-
            // result icon's width (searching). Behavior on
            // Layout.preferredWidth turns what would be a hard reflow
            // jump on the first keystroke into a smooth shrink, while
            // leaving zero dead space at the steady state.
            Item {
                id: headerSlot
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Math.max(headerActionStrip.implicitHeight,
                                                 Kirigami.Units.iconSizes.medium)
                readonly property real _iconReservation: Kirigami.Units.iconSizes.medium * panel.densityScale
                Layout.preferredWidth: panel.isSearching
                    ? (panel.showSearchResults && panel.currentResultIcon !== ""
                         ? _iconReservation : 0)
                    : headerActionStrip.implicitWidth
                Behavior on Layout.preferredWidth {
                    NumberAnimation {
                        id: headerSlotAnim
                        duration: Kirigami.Units.shortDuration
                        easing.type: Easing.OutQuart
                    }
                }
                clip: true

                HeaderActionStrip {
                    id: headerActionStrip
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // `visible: false` (not opacity:0) so the buttons stop
                    // hit-testing — hovering the empty slot mid-animation
                    // otherwise pops their tooltips.
                    visible: !panel.isSearching
                    showActionLabels: cfg.showActionLabels
                    hideMenuButtonLabel: cfg.hideMenuButtonLabel
                    headerActions: cfg.headerActions
                    updateChecker: panel.updateChecker
                    sessionActions: sessionActions
                    onActionTriggered: panel.closeRequested()
                }

                // Current search-result icon, shown in place of the power
                // buttons while searching. Fixed size — a fillHeight icon
                // rounds to different standard sizes as the header reflows,
                // making it visibly jump.
                ShadowedIcon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: headerSlot._iconReservation
                    height: headerSlot._iconReservation
                    visible: panel.showSearchResults && panel.currentResultIcon !== ""
                    source: panel.currentResultIcon
                    shadowEnabled: cfg.iconShadow
                }
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
            listDirectory: panel.plasmoidBridge.listDirectory
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

        // A little extra context for a certain well-known number.
        PlasmaComponents.ItemDelegate {
            Layout.fillWidth: true
            leftPadding: Kirigami.Units.largeSpacing
            rightPadding: Kirigami.Units.largeSpacing
            visible: panel.showSearchResults && !panel.isPrefixMode
                     && Number(searchBar.text.trim()) === 6 * 7
            implicitHeight: Math.max(panel.gridIconSize, _answerRow.implicitHeight) + Kirigami.Units.smallSpacing * 2
            onClicked: Qt.openUrlExternally("https://en.wikipedia.org/wiki/Phrases_from_The_Hitchhiker%27s_Guide_to_the_Galaxy")

            contentItem: RowLayout {
                id: _answerRow
                spacing: Kirigami.Units.largeSpacing

                Text {
                    Layout.preferredWidth: panel.gridIconSize
                    Layout.preferredHeight: panel.gridIconSize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Math.round(panel.gridIconSize * 0.8)
                    text: "🌍"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: "42"
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        // Intentionally left untranslated (not localizable copy).
                        text: "The Answer to the Ultimate Question of Life, the Universe, and Everything"
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        elide: Text.ElideRight
                    }
                }
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
                contextMenu.showForRunner(item.sourceIndex, actions)
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
                fontScale: panel.densityScale
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


    // -----------------------------------------------------------------------
    // Context menu
    // -----------------------------------------------------------------------

    LauncherActions {
        id: launcherActions
        applet: panel.appletInterface
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
        appletInterface: panel.appletInterface

        appActions: panel.plasmoidBridge.appActions
        launchAppAction: panel.plasmoidBridge.launchAppAction
        canManageInDiscover: panel.plasmoidBridge.canManageInDiscover
        openInDiscover: panel.plasmoidBridge.openInDiscover
        pinToTaskManager: launcherActions.pinToTaskManager
        addToDesktop: launcherActions.addToDesktop
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
