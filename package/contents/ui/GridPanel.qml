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

Kirigami.ShadowedRectangle {
    id: panel

    signal closeRequested()

    function shakeAllIcons() { appGrid.shakeAllIcons() }

    // Dev/testing flags (populated at build time from BUILDFLAGS)
    DevFlags { id: devFlags }

    // -- Derived properties --
    readonly property var appsModel: Plasmoid ? Plasmoid.appsModel : null
    readonly property bool isSearching: searchBar.text.length > 0
    readonly property bool showCatBar: (Plasmoid.configuration.showCategoryBar !== false)
                                       && !panel.isSearching && !panel.isPrefixMode
    readonly property int columns: Plasmoid.configuration.gridColumns || 7
    readonly property int rows: Plasmoid.configuration.gridRows || 4
    readonly property int scrollBarPolicy: Plasmoid.configuration.showScrollbars
                                           ? PlasmaComponents.ScrollBar.AsNeeded : PlasmaComponents.ScrollBar.AlwaysOff

    // -- Icon size mapping (0=Small/medium, 1=Medium/large, 2=Large/huge) --
    readonly property real gridIconSize: {
        var preset = Plasmoid.configuration.iconSize
        if (preset === 0) return Kirigami.Units.iconSizes.medium
        if (preset === 1) return Kirigami.Units.iconSizes.large
        return Kirigami.Units.iconSizes.huge
    }

    // -- Prefix mode detection --
    readonly property string prefixMode: {
        var t = searchBar.text
        if (t.startsWith("t:")) return "terminal"
        if (t.startsWith("?")) return "help"
        if (t.startsWith("/") || t.startsWith("~/")) return "files"
        if (t.startsWith(":")) return "command"
        return ""
    }
    readonly property bool isPrefixMode: prefixMode !== ""
    readonly property string prefixArgument: {
        var t = searchBar.text
        if (prefixMode === "terminal") return t.substring(2).trim()
        if (prefixMode === "command") return t.substring(1).trim()
        if (prefixMode === "files") return t.trim()
        return ""
    }

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
               : Kirigami.Units.cornerRadius * 2)

    readonly property real bgOpacity: Plasmoid.configuration.backgroundOpacity / 100
    color: nativePopup ? "transparent"
           : Qt.rgba(Kirigami.Theme.backgroundColor.r,
                     Kirigami.Theme.backgroundColor.g,
                     Kirigami.Theme.backgroundColor.b,
                     bgOpacity)

    border.width: nativePopup ? 0 : 1
    border.color: nativePopup ? "transparent"
                  : Qt.rgba(Kirigami.Theme.textColor.r,
                            Kirigami.Theme.textColor.g,
                            Kirigami.Theme.textColor.b,
                            0.15)

    shadow.size: nativePopup ? 0 : Kirigami.Units.gridUnit
    shadow.color: nativePopup ? "transparent" : Qt.rgba(0, 0, 0, 0.3)
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

    Component.onCompleted: {
        if (appsModel) {
            appsModel.hiddenApps = Plasmoid.configuration.hiddenApps || []
            appsModel.favoriteApps = Plasmoid.configuration.favoriteApps || []
            appsModel.maxRecentApps = columns
            appsModel.recentApps = Plasmoid.configuration.recentApps || []
            appsModel.sortMode = Plasmoid.configuration.sortMode || 0
            appsModel.launchCounts = launchCountsToMap(Plasmoid.configuration.launchCounts)
            appsModel.knownApps = Plasmoid.configuration.knownApps || []
            if (appsModel.knownApps.length === 0)
                appsModel.markAllKnown()
        }
    }

    onColumnsChanged: if (appsModel) appsModel.maxRecentApps = columns

    Binding {
        target: panel.appsModel
        property: "useSystemCategories"
        value: Plasmoid.configuration.useSystemCategories || false
    }

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

    // -- Reset state (called when showing the grid) --
    function resetState() {
        contextMenu.close()
        categoryBar.closeCategoryMenu()
        powerButtons.closeMenus()
        searchBar.text = ""
        var catBarEnabled = Plasmoid.configuration.showCategoryBar !== false
        var startFav = catBarEnabled && (Plasmoid.configuration.startWithFavorites || false)
        categoryBar.favoritesActive = startFav
        if (appsModel) {
            appsModel.searchText = ""
            appsModel.filterCategory = ""
            appsModel.showFavoritesOnly = startFav
            appsModel.hiddenApps = Plasmoid.configuration.hiddenApps || []
            appsModel.favoriteApps = Plasmoid.configuration.favoriteApps || []
            appsModel.maxRecentApps = columns
            appsModel.sortMode = Plasmoid.configuration.sortMode || 0
            appsModel.useSystemCategories = Plasmoid.configuration.useSystemCategories || false
            appsModel.launchCounts = launchCountsToMap(Plasmoid.configuration.launchCounts)
            appsModel.knownApps = Plasmoid.configuration.knownApps || []
            if (appsModel.knownApps.length === 0)
                appsModel.markAllKnown()
            if (Plasmoid.configuration.showRecentApps !== false)
                appsModel.recentApps = Plasmoid.configuration.recentApps || []
            else
                appsModel.recentApps = []
        }
        appGrid.editMode = false
        appGrid.selectedSwapIndex = -1
        appGrid.clearShuffles()
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        _needsScrollToTop = true
        searchBar.field.forceActiveFocus()
    }

    // -- Search focus management --
    // Centralized helpers to keep focus state clean across app results, runner results, and search bar.

    function focusAppResults(index) {
        runnerResults.currentIndex = -1
        searchResultsList.forceActiveFocus()
        searchResultsList.currentIndex = index
    }

    function focusRunnerResults(index) {
        searchResultsList.currentIndex = -1
        runnerResults.forceActiveFocus()
        runnerResults.currentIndex = index
    }

    readonly property bool hasRunnerResults: runnerResults.visible && runnerResults.count > 0

    function launchApp(index) {
        if (appsModel && index >= 0) {
            appsModel.launch(index)
            closeRequested()
        }
    }

    // Eat clicks so they don't pass through the panel
    MouseArea { anchors.fill: parent }

    // Handle Alt+letter mnemonics for category bar (including overflow items)
    Keys.onPressed: function(event) {
        if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            if (categoryBar.visible && categoryBar.selectByMnemonic(event.key))
                event.accepted = true
        }
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
                    interval: 200
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
                    if (number <= searchResultsList.count) {
                        panel.launchApp(number - 1)
                    } else {
                        var runnerIdx = number - 1 - searchResultsList.count
                        if (runnerIdx >= 0 && runnerIdx < runnerResults.count) {
                            if (Plasmoid.runRunnerResult(runnerIdx))
                                panel.closeRequested()
                        }
                    }
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
                        // Runner results handle their own Enter key
                        if (runnerResults.activeFocus)
                            return
                        var view = panel.isSearching ? searchResultsList : appGrid
                        if (view.currentIndex >= 0) panel.launchApp(view.currentIndex)
                    }
                }
                onMoveDown: {
                    if (panel.prefixMode === "files") {
                        prefixModeView.focusFileList()
                        return
                    }
                    if (panel.isSearching && !panel.isPrefixMode) {
                        if (searchResultsList.count > 0)
                            panel.focusAppResults(0)
                        else if (panel.hasRunnerResults)
                            panel.focusRunnerResults(0)
                    } else {
                        appGrid.forceActiveFocus()
                        if (appGrid.showRecents) {
                            appGrid.recentIndex = 0
                            appGrid.currentIndex = -1
                        } else {
                            appGrid.currentIndex = 0
                        }
                    }
                }
                onTabPressed: {
                    if (panel.isSearching) {
                        // Skip app results if only 1 item (Enter already launches it)
                        if (searchResultsList.count <= 1 && panel.hasRunnerResults)
                            panel.focusRunnerResults(0)
                        else if (searchResultsList.count > 0)
                            panel.focusAppResults(0)
                        else if (panel.hasRunnerResults)
                            panel.focusRunnerResults(0)
                    }
                }
            }

            PowerButtons {
                id: powerButtons
                onActionTriggered: panel.closeRequested()
            }
        }

        // -- Category bar --
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.15)
            visible: panel.showCatBar
        }

        CategoryBar {
            id: categoryBar
            visible: panel.showCatBar
            appsModel: panel.appsModel
            devExtraCategories: devFlags.extraCategories
            onFavoritesToggled: function(active) {
                categoryBar.favoritesActive = active
                if (!active)
                    appGrid.editMode = false
                if (panel.appsModel) {
                    panel.appsModel.showFavoritesOnly = active
                    if (active)
                        panel.appsModel.filterCategory = ""
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.15)
            visible: panel.showCatBar
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
            onFileOpened: panel.closeRequested()
            onDirectoryNavigated: function(path) {
                searchBar.text = path
            }
        }

        // -- Search results (app results + KRunner results) --
        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
            PlasmaComponents.ScrollBar.vertical.policy: panel.scrollBarPolicy
            visible: panel.isSearching && !panel.isPrefixMode

            Flickable {
                id: searchFlickable
                contentHeight: searchColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: searchColumn
                    width: searchFlickable.width
                    spacing: 0

                    SearchResultsList {
                        id: searchResultsList
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                        model: panel.isSearching ? panel.appsModel : null
                        searchField: searchBar.field
                        interactive: false
                        onLaunched: function(index) { panel.launchApp(index) }
                        onNavigatedPastEnd: {
                            if (panel.hasRunnerResults)
                                panel.focusRunnerResults(0)
                            else
                                panel.focusAppResults(0)
                        }
                        onNavigatedPastStart: {
                            if (panel.hasRunnerResults)
                                panel.focusRunnerResults(runnerResults.count - 1)
                            else
                                panel.focusAppResults(searchResultsList.count - 1)
                        }
                    }

                    // Divider between app results and runner results
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        Layout.bottomMargin: Kirigami.Units.smallSpacing
                        implicitHeight: 1
                        color: Qt.rgba(Kirigami.Theme.textColor.r,
                                       Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.15)
                        visible: runnerResults.visible && searchResultsList.count > 0
                    }

                    ListView {
                        id: runnerResults
                        Layout.fillWidth: true
                        Layout.preferredHeight: contentHeight
                        interactive: false
                        visible: panel.isSearching
                                 && Plasmoid.configuration.useExtraRunners !== false
                                 && count > 0
                        model: Plasmoid.runnerModel
                        currentIndex: -1
                        highlightMoveDuration: 0

                        Keys.onReturnPressed: {
                            if (currentIndex >= 0) {
                                if (Plasmoid.runRunnerResult(currentIndex))
                                    panel.closeRequested()
                            }
                        }
                        Keys.onEnterPressed: Keys.onReturnPressed

                        Keys.onTabPressed: {
                            if (currentIndex >= count - 1) {
                                if (searchResultsList.count > 0)
                                    panel.focusAppResults(0)
                                else
                                    panel.focusRunnerResults(0)
                            } else {
                                currentIndex++
                            }
                        }
                        Keys.onBacktabPressed: {
                            if (currentIndex <= 0) {
                                if (searchResultsList.count > 0)
                                    panel.focusAppResults(searchResultsList.count - 1)
                                else
                                    panel.focusRunnerResults(count - 1)
                            } else {
                                currentIndex--
                            }
                        }
                        Keys.onUpPressed: {
                            if (currentIndex > 0)
                                currentIndex--
                            else if (searchResultsList.count > 0)
                                panel.focusAppResults(searchResultsList.count - 1)
                        }
                        Keys.onDownPressed: {
                            if (currentIndex < count - 1)
                                currentIndex++
                        }

                        // Alt+number shortcuts and redirect typing back to search
                        Keys.onPressed: function(event) {
                            if (event.modifiers & Qt.AltModifier) {
                                var num = event.key - Qt.Key_0
                                var offset = searchResultsList.count
                                var runnerIdx = num - 1 - offset
                                if (num >= 1 && num <= 9 && runnerIdx >= 0 && runnerIdx < count) {
                                    if (Plasmoid.runRunnerResult(runnerIdx))
                                        panel.closeRequested()
                                    event.accepted = true
                                    return
                                }
                            }
                            if (event.text.length > 0 && !event.modifiers && searchBar.field) {
                                searchBar.field.forceActiveFocus()
                                searchBar.field.text += event.text
                                event.accepted = true
                            }
                        }

                        delegate: PlasmaComponents.ItemDelegate {
                            id: runnerDelegate
                            width: runnerResults.width
                            height: Kirigami.Units.iconSizes.huge + Kirigami.Units.smallSpacing * 2
                            highlighted: runnerResults.activeFocus && runnerResults.currentIndex === model.index

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.largeSpacing

                                // Alt+number shortcut badge (continues from app results)
                                Rectangle {
                                    property int shortcutNum: searchResultsList.count + model.index + 1
                                    visible: shortcutNum <= 9
                                    implicitWidth: runnerShortcutLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                                    radius: Kirigami.Units.cornerRadius
                                    color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                   Kirigami.Theme.highlightColor.g,
                                                   Kirigami.Theme.highlightColor.b, 0.15)
                                    border.width: 1
                                    border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                          Kirigami.Theme.textColor.g,
                                                          Kirigami.Theme.textColor.b, 0.2)

                                    PlasmaComponents.Label {
                                        id: runnerShortcutLabel
                                        anchors.centerIn: parent
                                        text: "Alt+" + String(parent.shortcutNum)
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.7
                                    }

                                    Accessible.ignored: true
                                }

                                Kirigami.Icon {
                                    implicitWidth: Kirigami.Units.iconSizes.huge
                                    implicitHeight: Kirigami.Units.iconSizes.huge
                                    source: model.decoration || "application-x-executable"
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    RowLayout {
                                        Layout.fillWidth: true
                                        PlasmaComponents.Label {
                                            Layout.fillWidth: true
                                            text: model.display || ""
                                            elide: Text.ElideRight
                                            color: runnerDelegate.highlighted
                                                   ? Kirigami.Theme.highlightedTextColor
                                                   : Kirigami.Theme.textColor
                                        }
                                        Rectangle {
                                            visible: (model.category || "") !== ""
                                            implicitWidth: runnerTypeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                                            implicitHeight: runnerTypeLabel.implicitHeight + Kirigami.Units.smallSpacing
                                            radius: Kirigami.Units.cornerRadius
                                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                           Kirigami.Theme.textColor.g,
                                                           Kirigami.Theme.textColor.b, 0.08)

                                            PlasmaComponents.Label {
                                                id: runnerTypeLabel
                                                anchors.centerIn: parent
                                                text: model.category || ""
                                                font: Kirigami.Theme.smallFont
                                                opacity: 0.6
                                            }
                                        }
                                    }
                                    PlasmaComponents.Label {
                                        Layout.fillWidth: true
                                        text: model.subtext || ""
                                        elide: Text.ElideRight
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.6
                                        visible: text.length > 0
                                        color: runnerDelegate.highlighted
                                               ? Kirigami.Theme.highlightedTextColor
                                               : Kirigami.Theme.textColor
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: runnerResults.currentIndex = model.index
                                onClicked: {
                                    if (Plasmoid.runRunnerResult(model.index))
                                        panel.closeRequested()
                                }
                            }
                        }
                    }
                }
            }
        }

        // -- App grid --
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !panel.isSearching && !panel.isPrefixMode

            PlasmaComponents.ScrollView {
                anchors.fill: parent
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                PlasmaComponents.ScrollBar.vertical.policy: panel.scrollBarPolicy

                AppGridView {
                    id: appGrid
                    model: !panel.isSearching ? panel.appsModel : null
                    appsModel: panel.appsModel
                    columns: panel.columns
                    iconSize: panel.gridIconSize
                    searchField: searchBar.field
                    showRecentApps: Plasmoid.configuration.showRecentApps !== false
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
                    onFavoritesOrderChanged: {
                        if (panel.appsModel)
                            Plasmoid.configuration.favoriteApps = panel.appsModel.favoriteApps
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

            // Edit mode help text
            Rectangle {
                anchors.bottom: editModeBtn.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                z: 20
                visible: appGrid.editMode
                width: helpLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                height: helpLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.cornerRadius
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b, 0.9)

                PlasmaComponents.Label {
                    id: helpLabel
                    anchors.centerIn: parent
                    text: appGrid.selectedSwapIndex < 0
                          ? i18nd("dev.xarbit.appgrid", "Click an icon to select it, then click another to swap positions")
                          : i18nd("dev.xarbit.appgrid", "Now click another icon to swap, or click again to deselect")
                    font: Kirigami.Theme.smallFont
                }
            }

            // Edit mode button — visible only in favorites tab
            PlasmaComponents.ToolButton {
                id: editModeBtn
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Kirigami.Units.smallSpacing
                z: 20
                visible: categoryBar.favoritesActive
                icon.name: appGrid.editMode ? "dialog-ok-apply" : "document-edit"
                checked: appGrid.editMode
                onClicked: {
                    appGrid.editMode = !appGrid.editMode
                    appGrid.selectedSwapIndex = -1
                    if (!appGrid.editMode)
                        appGrid.favoritesOrderChanged()
                }

                PlasmaComponents.ToolTip.text: appGrid.editMode ? i18nd("dev.xarbit.appgrid", "Done") : i18nd("dev.xarbit.appgrid", "Reorder favorites")
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
            }

        }
    }

    // -----------------------------------------------------------------------
    // Context menu
    // -----------------------------------------------------------------------

    AppContextMenu {
        id: contextMenu
        appsModel: panel.appsModel
    }
}
