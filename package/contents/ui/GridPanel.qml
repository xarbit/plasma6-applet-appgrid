/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Reusable grid panel content. Used by GridWindow (fullscreen/centered modes)
    and as native Plasma popup (near panel icon mode).
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "favoriteid.js" as FavoriteId

Kirigami.ShadowedRectangle {
    id: panel

    signal closeRequested()
    // Plasmoid root (kicker). Deliberately `var`, not typed as PlasmoidItem,
    // for two reasons: typing it would force every consumer to import
    // `org.kde.plasma.plasmoid`, and keeping the contract structural lets
    // tests pass plain QtObject mocks that expose the same properties
    // (dragSource, isDragInFlight, closeWindow(), favoritesDragProxy, …).
    property var appletInterface: null

    function shakeAllIcons() {
        appGrid.shakeAllIcons()
        categoryGridView.shakeAllIcons()
    }

    // Dev/testing flags (populated at build time from BUILDFLAGS)
    DevFlags { id: devFlags }

    // -- Configuration (single source of truth for all config reads) --
    readonly property var appsModel: Plasmoid ? Plasmoid.appsModel : null
    readonly property int columns: Plasmoid.configuration.gridColumns || 7
    readonly property int rows: Plasmoid.configuration.gridRows || 4
    readonly property int sortMode: Plasmoid.configuration.sortMode || 0
    readonly property bool cfgShowCategoryBar: Plasmoid.configuration.showCategoryBar !== false
    readonly property bool cfgStartWithFavorites: Plasmoid.configuration.startWithFavorites !== false
    readonly property bool cfgShowRecentApps: Plasmoid.configuration.showRecentApps !== false
    readonly property bool cfgShowDividers: Plasmoid.configuration.showDividers !== false
    readonly property bool cfgShowTooltips: Plasmoid.configuration.showTooltips !== false
    readonly property bool cfgShowNewAppBadge: Plasmoid.configuration.showNewAppBadge !== false
    readonly property bool cfgHideLabelsOnFavorites: Plasmoid.configuration.hideLabelsOnFavorites === true
    readonly property bool cfgShowScrollbars: Plasmoid.configuration.showScrollbars !== false
    readonly property int scrollBarPolicy: cfgShowScrollbars
                                           ? PlasmaComponents.ScrollBar.AsNeeded : PlasmaComponents.ScrollBar.AlwaysOff

    // -- Sort helpers --
    readonly property bool isSortByCategory: sortMode === 2

    // -- View state --
    readonly property bool isSearching: searchBar.text.length > 0
    readonly property bool isFavoritesActive: categoryBar.favoritesActive
    readonly property bool showCatBar: cfgShowCategoryBar && !isSearching && !isPrefixMode
    readonly property bool showCategoryGrid: isSortByCategory && !isFavoritesActive
                                             && !isSearching && !isPrefixMode
    readonly property bool showAppGrid: !isSearching && !isPrefixMode && !showCategoryGrid
    readonly property bool showSearchResults: isSearching && !isPrefixMode

    // -- Icon size mapping (0=Small/medium, 1=Medium/large, 2=Large/huge) --
    readonly property real gridIconSize: {
        var preset = Plasmoid.configuration.iconSize
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

    // -- Cell size (icon-based, no circular dependency) --
    readonly property real estCellWidth: gridIconSize + Kirigami.Units.gridUnit * 2
                                         + Kirigami.Units.smallSpacing * 2
    readonly property real estCellHeight: gridIconSize + Kirigami.Units.gridUnit * 2
                                          + Kirigami.Units.smallSpacing * 2

    // -- Panel sizing --
    // Always use icon-based cell estimates to avoid circular dependency
    // (panel width → grid cellWidth → grid width → panel width).
    readonly property real panelMargin: nativePopup ? Kirigami.Units.largeSpacing : Kirigami.Units.largeSpacing * 2
    readonly property real headerHeight: Kirigami.Units.gridUnit * 5
    readonly property real panelWidth: estCellWidth * columns + panelMargin * 2
    readonly property real panelHeight: estCellHeight * rows + panelMargin * 2 + headerHeight

    width: Math.min(panelWidth, Screen.width * 0.9)
    height: Math.min(panelHeight, Screen.height * 0.9)

    Layout.preferredWidth: width
    Layout.preferredHeight: height
    Layout.minimumWidth: nativePopup ? Kirigami.Units.gridUnit * 12 : width
    Layout.minimumHeight: nativePopup ? Kirigami.Units.gridUnit * 12 : height
    radius: nativePopup ? 0
            : (Plasmoid.configuration.overrideRadius
               ? Plasmoid.configuration.cornerRadius
               : Kirigami.Units.cornerRadius)

    readonly property real bgOpacity: Plasmoid.configuration.backgroundOpacity / 100
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
        appsModel.hiddenApps = Plasmoid.configuration.hiddenApps || []
        // Favorites are loaded from KAStatsFavoritesModel after migration —
        // see sharedFavoritesLoader.onStatusChanged.
        appsModel.maxRecentApps = columns
        appsModel.sortMode = sortMode
        appsModel.useSystemCategories = Plasmoid.configuration.useSystemCategories !== false
        appsModel.sortFavoritesAlphabetically = Plasmoid.configuration.sortFavoritesAlphabetically === true
        appsModel.launchCounts = launchCountsToMap(Plasmoid.configuration.launchCounts)
        appsModel.knownApps = Plasmoid.configuration.knownApps || []
        appsModel.recentApps = cfgShowRecentApps
            ? (Plasmoid.configuration.recentApps || []) : []
        if (appsModel.knownApps.length === 0)
            appsModel.markAllKnown()
    }

    Component.onCompleted: syncModelFromConfig()
    onColumnsChanged: if (appsModel) appsModel.maxRecentApps = columns

    Connections {
        target: panel.appsModel
        function onRecentAppsChanged() {
            Plasmoid.configuration.recentApps = panel.appsModel.recentApps
        }
        function onLaunchCountsChanged() {
            Plasmoid.configuration.launchCounts = panel.launchCountsToList(panel.appsModel.launchCounts)
        }
        function onKnownAppsChanged() {
            Plasmoid.configuration.knownApps = panel.appsModel.knownApps
        }
    }

    // -- KActivities-backed favorites (always the source of truth) --
    // SharedFavoritesProvider.qml isolates the org.kde.plasma.private.kicker
    // import so a missing Kicker plugin is logged rather than crashing.
    Loader {
        id: sharedFavoritesLoader
        active: true
        source: "SharedFavoritesProvider.qml"
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("AppGrid: org.kde.plasma.private.kicker plugin missing — favorites disabled")
                return
            }
            if (status === Loader.Ready && item) {
                item.initForClient("dev.xarbit.appgrid.favorites.instance-" + Plasmoid.id)
                // Probe the well-known Kicker::FavoriteIdRole at runtime
                // (see _kickerFavoriteIdRole comment). If the data at that
                // role isn't a string, Plasma's enum has shifted and reorder
                // is left inert rather than reading wrong data.
                if (item.count > 0) {
                    const probe = item.data(item.index(0, 0), panel._kickerFavoriteIdRole)
                    if (typeof probe === "string") {
                        panel.favoriteIdRole = panel._kickerFavoriteIdRole
                    } else {
                        console.warn("AppGrid: FavoriteIdRole probe failed (got " + typeof probe
                                     + "); favorites reorder will be inert. Kicker enum may have shifted.")
                    }
                } else {
                    // No entries yet — accept the well-known value; the probe
                    // re-runs once entries land via onRowsInserted below.
                    panel.favoriteIdRole = panel._kickerFavoriteIdRole
                }
                // Migration + initial mirror are deferred until the model is
                // 'enabled' — KAStats only honours portOldFavorites once
                // kactivitymanagerd has finished initialising. See Connections
                // block below.
                if (item.enabled) {
                    panel._maybeMigrateAndMirror()
                }
            }
        }
    }

    // Called after KAStatsFavoritesModel.enabled flips true, OR immediately
    // if it was already true at load time. Idempotent and self-healing:
    // if a prior migration attempt set the flag without actually populating
    // KAStats (e.g. attempted while the model was disabled), this retries
    // when both the model is empty AND the local backup still has entries.
    // Migration entry point. Idempotent and self-healing: as long as KAStats
    // holds fewer entries than the local backup, we (re)issue portOldFavorites.
    // The model finishes loading on a 500ms timer internally; the QAbstractItemModel
    // signals below pick that up and call _mirrorFavorites again.
    function _maybeMigrateAndMirror() {
        const item = sharedFavoritesLoader.item
        if (!item) return
        if (favoriteIdRole < 0) {
            // Role probe hasn't resolved yet — try once it has, on the next
            // model signal. Skip mirror; nothing useful to do.
            return
        }

        const local = Plasmoid.configuration.favoriteApps || []

        // Build the union of the local backup and whatever KAStats already
        // holds. portOldFavorites's saveOrdering OVERWRITES the stored list
        // with the argument, so passing only the local backup would drop
        // any favorites added later via context menu. The union preserves
        // everything.
        const existing = []
        for (let i = 0; i < item.count; ++i) {
            const v = item.data(item.index(i, 0), favoriteIdRole)
            if (v) existing.push(v.toString())
        }
        const seen = {}
        const merged = []
        const pushIfNew = function(id) {
            const prefixed = FavoriteId.toPrefixed(id)
            if (seen[prefixed]) return
            seen[prefixed] = true
            merged.push(prefixed)
        }
        // Existing KAStats entries first to preserve their order, then any
        // local-only ones appended at the end.
        existing.forEach(pushIfNew)
        local.forEach(pushIfNew)

        if (merged.length > item.count)
            item.portOldFavorites(merged)

        panel._mirrorFavorites()
    }

    // KAStatsFavoritesModel's `favorites` property is a no-op in upstream
    // Kicker, so we read favoriteIds row-by-row instead. AppFilterModel
    // matches against bare storage IDs; we strip the scheme prefix when
    // present (see favoriteid.js). Resolved imperatively in
    // sharedFavoritesLoader's onStatusChanged once the model's roleNames()
    // is available. -1 means "not yet known"; findFavoriteRow and
    // _mirrorFavorites guard on that.
    property int favoriteIdRole: -1

    // Kicker::FavoriteIdRole == Qt::UserRole + 3 == 259. QML cannot read
    // QAbstractItemModel::roleNames() (not Q_INVOKABLE on Qt6), so we
    // hard-code the well-known value and probe it at runtime (below). If
    // Plasma ever shifts the enum the probe falls back to disabling reorder
    // rather than misreading data at a stale role index.
    readonly property int _kickerFavoriteIdRole: 259

    function _mirrorFavorites() {
        if (!panel.appsModel || !panel.sharedFavoritesModel) return
        if (favoriteIdRole < 0) return
        const model = panel.sharedFavoritesModel
        const ids = []
        for (let i = 0; i < model.count; ++i) {
            const raw = model.data(model.index(i, 0), favoriteIdRole)
            if (!raw) continue
            ids.push(FavoriteId.stripPrefix(raw))
        }
        panel.appsModel.favoriteApps = ids
    }

    Connections {
        target: sharedFavoritesLoader.item
        ignoreUnknownSignals: true
        function onEnabledChanged() {
            if (sharedFavoritesLoader.item && sharedFavoritesLoader.item.enabled)
                panel._maybeMigrateAndMirror()
        }
    }

    readonly property var sharedFavoritesModel: sharedFavoritesLoader.item

    // Mirror shared model into proxy model so the grid view updates.
    // KAStatsFavoritesModel does not emit `favoritesChanged` despite the
    // Q_PROPERTY declaration — upstream Kicker leaves it as a stub. Use the
    // QAbstractItemModel signals which are emitted on every change.
    // KAStatsFavoritesModel does not emit `favoritesChanged` despite the
    // Q_PROPERTY declaration — upstream Kicker leaves it as a stub. We listen
    // to QAbstractItemModel signals instead, which fire on every change.
    // Coalesce bursts of model-change signals: when KAStats reorders or
    // reloads, several of insert/remove/move/reset/layoutChanged/dataChanged
    // can fire back-to-back. We schedule one mirror per event-loop turn
    // instead of mirroring on every signal.
    // The mirror only needs to run when AppFilterModel actually serves the
    // favorites view (alpha-sort mode). In normal drag-reorder mode the
    // GridView reads sharedFavoritesModel directly, so there's nothing to
    // mirror into.
    readonly property bool mirrorRequired: Plasmoid.configuration.sortFavoritesAlphabetically === true

    Timer {
        id: mirrorCoalesce
        interval: 0
        repeat: false
        onTriggered: {
            if (!Plasmoid.configuration.favoritesPortedToKAstats
                    && panel.sharedFavoritesModel
                    && panel.sharedFavoritesModel.count > 0) {
                Plasmoid.configuration.favoritesPortedToKAstats = true
            }
            if (panel.mirrorRequired)
                panel._mirrorFavorites()
        }
    }

    // Catch up the proxy when the user enables alpha-sort mid-session.
    onMirrorRequiredChanged: {
        if (mirrorRequired) mirrorCoalesce.restart()
    }

    Connections {
        target: panel.sharedFavoritesModel
        ignoreUnknownSignals: true
        function _scheduleMirror() {
            // Migration finalisation still needs to happen even when not
            // mirroring (so the flag flips once KAStats has data).
            mirrorCoalesce.restart()
        }
        function onRowsInserted() { _scheduleMirror() }
        function onRowsRemoved() { _scheduleMirror() }
        function onRowsMoved() { _scheduleMirror() }
        function onModelReset() { _scheduleMirror() }
        function onLayoutChanged() { _scheduleMirror() }
        function onDataChanged() { _scheduleMirror() }
    }


    // -- Reset state (called when showing the grid) --
    function resetState() {
        contextMenu.close()
        categoryBar.closeCategoryMenu()
        categoryBar.resetScroll()
        powerButtons.closeMenus()
        searchBar.text = ""

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
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        categoryGridView.contentY = 0
        categoryGridView.currentIndex = -1
        categoryGridView.recentIndex = -1
        _needsScrollToTop = true
        searchBar.field.forceActiveFocus()
    }

    function launchSearchResult(index) {
        var item = Plasmoid.searchModel.get(index)
        if (!item) return
        if (item.resultType === "app") {
            launchApp(item.sourceIndex)
        } else {
            if (Plasmoid.runRunnerResult(item.sourceIndex))
                closeRequested()
        }
    }

    function launchApp(index) {
        if (appsModel && index >= 0) {
            appsModel.launch(index)
            closeRequested()
        }
    }

    // Eat clicks so they don't pass through the panel
    MouseArea { anchors.fill: parent }

    // Handle Alt+letter mnemonics for category bar
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Alt)
            categoryBar.altHeld = true
        if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            if (categoryBar.visible && categoryBar.selectByMnemonic(event.key))
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
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            SearchBar {
                id: searchBar
                property string savedCategory: ""
                property bool savedFavorites: false
                property bool filtersCleared: false

                // Debounce KRunner queries — fires after typing pauses
                Timer {
                    id: runnerDebounce
                    interval: 100
                    onTriggered: {
                        if (Plasmoid.runnerSourceModel) {
                            var q = searchBar.text
                            var searching = q.length > 0 && !panel.isPrefixMode
                            Plasmoid.runnerSourceModel.queryString = searching ? q : ""
                        }
                    }
                }

                onTextChanged: {
                    var searching = text.length > 0 && !panel.isPrefixMode
                    var searchAll = Plasmoid.configuration.searchAll !== false

                    if (searching && searchAll && !filtersCleared) {
                        savedCategory = panel.appsModel ? panel.appsModel.filterCategory : ""
                        savedFavorites = categoryBar.favoritesActive
                        if (panel.appsModel) {
                            panel.appsModel.filterCategory = ""
                            panel.appsModel.showFavoritesOnly = false
                        }
                        filtersCleared = true
                    } else if (!searching && filtersCleared) {
                        if (panel.appsModel) {
                            panel.appsModel.filterCategory = savedCategory
                            panel.appsModel.showFavoritesOnly = savedFavorites
                        }
                        categoryBar.favoritesActive = savedFavorites
                        filtersCleared = false
                    }

                    // App filter is instant (cheap string matching)
                    if (panel.appsModel)
                        panel.appsModel.searchText = panel.isPrefixMode ? "" : text

                    // KRunner query is debounced (expensive D-Bus calls)
                    if (searching)
                        runnerDebounce.restart()
                    else if (Plasmoid.runnerSourceModel)
                        Plasmoid.runnerSourceModel.queryString = ""
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
                        Plasmoid.runInTerminal(panel.prefixArgument, Plasmoid.configuration.terminalShell || "")
                        panel.closeRequested()
                    } else if (panel.prefixMode === "command") {
                        Plasmoid.runCommand(panel.prefixArgument, Plasmoid.configuration.terminalShell || "")
                        panel.closeRequested()
                    } else if (panel.prefixMode === "files") {
                        prefixModeView.activateFileCurrent()
                    } else if (!panel.isPrefixMode) {
                        if (panel.isSearching) {
                            var idx = searchResultsList.currentIndex >= 0 ? searchResultsList.currentIndex : 0
                            if (searchResultsList.count > 0) panel.launchSearchResult(idx)
                        } else {
                            if (appGrid.currentIndex >= 0) panel.launchApp(appGrid.currentIndex)
                        }
                    }
                }
                function navigateToResults() {
                    if (panel.isSearching && !panel.isPrefixMode) {
                        if (searchResultsList.count > 1) {
                            searchResultsList.forceActiveFocus()
                            searchResultsList.currentIndex = 1
                        } else if (searchResultsList.count === 1) {
                            searchResultsList.forceActiveFocus()
                        }
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
                    navigateToResults()
                }
                onTabPressed: navigateToResults()
            }

            PowerButtons {
                id: powerButtons
                visible: Plasmoid.configuration.showSessionButtons !== false
                onActionTriggered: panel.closeRequested()
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
            appsModel: panel.appsModel
            devExtraCategories: devFlags.extraCategories
            favoritesFirst: panel.cfgStartWithFavorites
            isSortByCategory: panel.isSortByCategory
            scrollOnlyMode: panel.showCategoryGrid
            hideEmptyCategories: Plasmoid.configuration.hideEmptyCategories !== false
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
            onFileOpened: panel.closeRequested()
            onDirectoryNavigated: function(path) {
                searchBar.text = path
            }
        }

        // -- Unified search results --
        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            PlasmaComponents.ScrollBar.vertical.policy: panel.scrollBarPolicy
            visible: panel.showSearchResults

            SearchResultsList {
                id: searchResultsList
                model: panel.isSearching ? Plasmoid.searchModel : null
                iconSize: panel.gridIconSize
                showDividers: panel.cfgShowDividers
                animateHighlight: (Plasmoid.configuration.hoverAnimation || 0) > 0
                searchField: searchBar.field
                onLaunched: function(index) { panel.launchSearchResult(index) }
                onContextMenuRequested: function(index, storageId, desktopFile) {
                    if (storageId)
                        contextMenu.showForApp(-1, storageId, desktopFile)
                }
            }
        }

        // -- Category grid (By Category sort) --
        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            PlasmaComponents.ScrollBar.vertical.policy: panel.scrollBarPolicy
            visible: panel.showCategoryGrid

            CategoryGridView {
                id: categoryGridView
                searchField: searchBar.field
                appsModel: panel.appsModel
                groupedApps: panel.showCategoryGrid && panel.appsModel
                    ? panel.appsModel.groupedByCategory : []
                cellWidth: Math.floor(categoryGridView.width / panel.columns)
                cellHeight: panel.gridIconSize
                            + Kirigami.Units.gridUnit * 3
                            + Kirigami.Units.smallSpacing * 2
                iconSize: panel.gridIconSize
                showDividers: panel.cfgShowDividers
                showTooltips: panel.cfgShowTooltips
                showNewAppBadge: panel.cfgShowNewAppBadge
                showRecents: panel.cfgShowRecentApps
                             && panel.appsModel
                             && panel.appsModel.recentApps.length > 0
                             && !panel.isFavoritesActive
                             && !panel.cfgStartWithFavorites
                onLaunched: function(proxyIndex) { panel.launchApp(proxyIndex) }
                onRecentLaunched: function(storageId) {
                    if (panel.appsModel) {
                        panel.appsModel.launchByStorageId(storageId)
                        panel.closeRequested()
                    }
                }
                onContextMenuRequested: function(proxyIndex, storageId, desktopFile) {
                    contextMenu.showForApp(proxyIndex, storageId, desktopFile)
                }
            }
        }

        // -- App grid --
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: panel.showAppGrid

            PlasmaComponents.ScrollView {
                anchors.fill: parent
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                PlasmaComponents.ScrollBar.vertical.policy: panel.scrollBarPolicy

                AppGridView {
                    id: appGrid
                    // In favorites tab, drive the grid from KAStats directly so
                    // reorder animations and pointer grabs work natively.
                    // Elsewhere, or when alphabetical sort is enabled (which
                    // KAStats does not support), use the filter proxy.
                    model: panel.isSearching ? null
                           : (panel.isFavoritesActive
                              && panel.sharedFavoritesModel
                              && !Plasmoid.configuration.sortFavoritesAlphabetically
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
                    searchField: searchBar.field
                    showRecentApps: panel.cfgShowRecentApps
                    startWithFavorites: panel.cfgStartWithFavorites
                    favoritesActive: panel.isFavoritesActive
                    showDividers: panel.cfgShowDividers
                    showTooltips: panel.cfgShowTooltips
                    showNewAppBadge: panel.cfgShowNewAppBadge
                    hideLabelsOnFavorites: panel.cfgHideLabelsOnFavorites
                    animateHighlight: (Plasmoid.configuration.hoverAnimation || 0) > 0
                    shuffleOverlayParent: shuffleOverlay
                    onOriginYChanged: {
                        if (panel._needsScrollToTop) {
                            contentY = originY
                            panel._needsScrollToTop = false
                        }
                    }
                    onLaunched: function(index) { panel.launchApp(index) }
                    onRecentLaunched: function(storageId) {
                        if (panel.appsModel) {
                            panel.appsModel.launchByStorageId(storageId)
                            panel.closeRequested()
                        }
                    }
                    onContextMenuRequested: function(index, storageId, desktopFile) {
                        contextMenu.showForApp(index, storageId, desktopFile)
                    }
                    onShuffleAnimRequested: function(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex) {
                        shuffleOverlay.startAnim(fromX, fromY, toX, toY, fromIcon, toIcon, fromIndex, toIndex)
                    }
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
    }
}
