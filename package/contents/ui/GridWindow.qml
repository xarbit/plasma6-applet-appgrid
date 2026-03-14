/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Fullscreen overlay window containing the application grid panel.
    Uses LayerShellQt (via C++ configureWindow) to appear as a Wayland
    overlay without KWin window decorations or taskbar entries.
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.milou as Milou

Window {
    id: root

    // -- Public interface --
    property var appletInterface: null

    // -- Derived properties --
    readonly property var appsModel: Plasmoid ? Plasmoid.appsModel : null
    readonly property bool isSearching: searchBar.text.length > 0
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

    // -- Window setup --
    width: Screen.width
    height: Screen.height
    x: 0; y: 0
    visible: false
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint | Qt.Tool

    property bool windowConfigured: false
    property bool _needsScrollToTop: false

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
            appsModel.maxRecentApps = root.columns
            appsModel.recentApps = Plasmoid.configuration.recentApps || []
            appsModel.sortMode = Plasmoid.configuration.sortMode || 0
            appsModel.launchCounts = root.launchCountsToMap(Plasmoid.configuration.launchCounts)
            appsModel.knownApps = Plasmoid.configuration.knownApps || []
            // First run: mark all current apps as known
            if (appsModel.knownApps.length === 0)
                appsModel.markAllKnown()
        }
    }

    // Keep maxRecentApps in sync with configured columns
    onColumnsChanged: if (appsModel) appsModel.maxRecentApps = columns

    // Persist model state to config when it changes
    Connections {
        target: appsModel
        function onRecentAppsChanged() {
            Plasmoid.configuration.recentApps = appsModel.recentApps
        }
        function onLaunchCountsChanged() {
            Plasmoid.configuration.launchCounts = root.launchCountsToList(appsModel.launchCounts)
        }
        function onKnownAppsChanged() {
            Plasmoid.configuration.knownApps = appsModel.knownApps
        }
    }

    // -----------------------------------------------------------------------
    // Blur management
    // -----------------------------------------------------------------------

    function applyBlur() {
        if (Plasmoid.configuration.enableBlur && visible) {
            var pw = Math.round(panel.width)
            var ph = Math.round(panel.height)
            var px = Math.round((root.width - pw) / 2)
            var py = Math.round((root.height - ph) / 2)
            Plasmoid.setBlurBehind(root, true, px, py, pw, ph, panel.radius)
        } else {
            Plasmoid.setBlurBehind(root, false, 0, 0, 0, 0, 0)
        }
    }

    onWidthChanged: if (visible) applyBlur()
    onHeightChanged: if (visible) applyBlur()

    // -----------------------------------------------------------------------
    // Grid lifecycle
    // -----------------------------------------------------------------------

    function showGrid() {
        contextMenu.close()
        searchBar.text = ""
        if (appsModel) {
            appsModel.searchText = ""
            appsModel.filterCategory = ""
            appsModel.hiddenApps = Plasmoid.configuration.hiddenApps || []
            appsModel.favoriteApps = Plasmoid.configuration.favoriteApps || []
            appsModel.maxRecentApps = root.columns
            appsModel.sortMode = Plasmoid.configuration.sortMode || 0
            appsModel.launchCounts = root.launchCountsToMap(Plasmoid.configuration.launchCounts)
            appsModel.knownApps = Plasmoid.configuration.knownApps || []
            if (appsModel.knownApps.length === 0)
                appsModel.markAllKnown()
            if (Plasmoid.configuration.showRecentApps !== false)
                appsModel.recentApps = Plasmoid.configuration.recentApps || []
            else
                appsModel.recentApps = []
        }
        if (!windowConfigured) {
            Plasmoid.configureWindow(root)
            windowConfigured = true
        }
        appGrid.contentY = appGrid.originY
        appGrid.currentIndex = -1
        appGrid.recentIndex = -1
        searchResultsList.contentY = searchResultsList.originY
        visible = true
        root._needsScrollToTop = true
        applyBlur()
        requestActivate()
        openAnim.start()
        searchBar.field.forceActiveFocus()
    }

    function closeGrid() {
        contextMenu.close()
        closeAnim.start()
    }

    function launchApp(index) {
        if (appsModel && index >= 0) {
            appsModel.launch(index)
            if (appletInterface)
                appletInterface.closeWindow()
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // Alt+1 through Alt+9 handled via search bar key forwarding

    // -----------------------------------------------------------------------
    // Background (click to close)
    // -----------------------------------------------------------------------

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root.appletInterface)
                root.appletInterface.closeWindow()
        }
    }

    // -----------------------------------------------------------------------
    // Main panel
    // -----------------------------------------------------------------------

    Kirigami.ShadowedRectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(appGrid.cellWidth * root.columns
                       + Kirigami.Units.largeSpacing * 4, Screen.width * 0.9)
        height: Math.min(appGrid.cellHeight * root.rows
                        + Kirigami.Units.largeSpacing * 4
                        + Kirigami.Units.gridUnit * 5, Screen.height * 0.9)
        radius: Plasmoid.configuration.overrideRadius
                ? Plasmoid.configuration.cornerRadius
                : Kirigami.Units.cornerRadius * 2
        opacity: 0.0
        scale: 1.15
        transformOrigin: Item.Center

        readonly property real bgOpacity: Plasmoid.configuration.backgroundOpacity / 100
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                       Kirigami.Theme.backgroundColor.g,
                       Kirigami.Theme.backgroundColor.b,
                       bgOpacity)

        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b,
                              0.15)

        shadow.size: Kirigami.Units.gridUnit
        shadow.color: Qt.rgba(0, 0, 0, 0.3)
        shadow.xOffset: 0
        shadow.yOffset: Kirigami.Units.smallSpacing

        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.largeSpacing

            // -- Header --
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                SearchBar {
                    id: searchBar
                    onTextChanged: {
                        if (appsModel)
                            appsModel.searchText = root.isPrefixMode ? "" : text
                    }
                    onAltNumberPressed: function(number) {
                        if (root.isSearching && !root.isPrefixMode
                            && number <= searchResultsList.count) {
                            root.launchApp(number - 1)
                        }
                    }
                    onAccepted: {
                        if (root.prefixMode === "terminal") {
                            Plasmoid.runInTerminal(root.prefixArgument)
                            if (root.appletInterface) root.appletInterface.closeWindow()
                        } else if (root.prefixMode === "command") {
                            Plasmoid.runCommand(root.prefixArgument)
                            if (root.appletInterface) root.appletInterface.closeWindow()
                        } else if (root.prefixMode === "files") {
                            prefixModeView.activateFileCurrent()
                        } else if (!root.isPrefixMode) {
                            var view = root.isSearching ? searchResultsList : appGrid
                            if (view.currentIndex >= 0) root.launchApp(view.currentIndex)
                        }
                    }
                    onMoveDown: {
                        if (root.prefixMode === "files") {
                            prefixModeView.focusFileList()
                            return
                        }
                        if (root.isSearching && !root.isPrefixMode) {
                            if (searchResultsList.count > 0) {
                                searchResultsList.forceActiveFocus()
                                searchResultsList.currentIndex = 0
                            } else if (runnerResults.visible && runnerResults.count > 0) {
                                runnerResults.forceActiveFocus()
                                runnerResults.currentIndex = 0
                            }
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
                        if (root.isSearching) {
                            if (searchResultsList.count > 0) {
                                searchResultsList.forceActiveFocus()
                                searchResultsList.currentIndex = Math.min(
                                    searchResultsList.currentIndex + 1,
                                    searchResultsList.count - 1)
                            } else if (runnerResults.visible && runnerResults.count > 0) {
                                runnerResults.forceActiveFocus()
                                runnerResults.currentIndex = 0
                            }
                        }
                    }
                }

                PowerButtons {
                    onActionTriggered: root.closeGrid()
                }
            }

            // -- Category bar --
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r,
                               Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.15)
                visible: !root.isSearching && !root.isPrefixMode
            }

            CategoryBar {
                visible: !root.isSearching && !root.isPrefixMode
                appsModel: root.appsModel
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r,
                               Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.15)
                visible: !root.isSearching && !root.isPrefixMode
            }

            // -- Prefix mode view --
            PrefixModeView {
                id: prefixModeView
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.isPrefixMode
                mode: root.prefixMode
                argument: root.prefixArgument
                searchField: searchBar.field
                onCommandExecuted: {
                    if (root.appletInterface) root.appletInterface.closeWindow()
                }
                onFileOpened: {
                    if (root.appletInterface) root.appletInterface.closeWindow()
                }
                onDirectoryNavigated: function(path) {
                    searchBar.text = path
                }

            }

            // -- Search results (app results + KRunner results) --
            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                PlasmaComponents.ScrollBar.vertical.policy: root.scrollBarPolicy
                visible: root.isSearching && !root.isPrefixMode

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
                            model: root.isSearching ? appsModel : null
                            searchField: searchBar.field
                            interactive: false
                            onLaunched: function(index) { root.launchApp(index) }
                            onNavigatedPastEnd: {
                                if (runnerResults.visible && runnerResults.count > 0) {
                                    runnerResults.forceActiveFocus()
                                    runnerResults.currentIndex = 0
                                }
                            }
                        }

                        // KRunner results
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                           Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b, 0.15)
                            visible: runnerResults.visible
                        }

                        PlasmaComponents.Label {
                            Layout.leftMargin: Kirigami.Units.largeSpacing
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            text: i18n("More Results")
                            font.bold: true
                            opacity: 0.7
                            visible: runnerResults.visible
                        }

                        Milou.ResultsView {
                            id: runnerResults
                            Layout.fillWidth: true
                            Layout.preferredHeight: contentHeight
                            interactive: false
                            queryString: root.isSearching && !root.isPrefixMode ? searchBar.text : ""
                            queryField: searchBar.field
                            limit: 5
                            visible: root.isSearching
                                     && Plasmoid.configuration.useExtraRunners !== false
                                     && count > 0
                            onActivated: {
                                if (root.appletInterface)
                                    root.appletInterface.closeWindow()
                            }
                        }
                    }
                }
            }

            // -- App grid --
            PlasmaComponents.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                PlasmaComponents.ScrollBar.vertical.policy: root.scrollBarPolicy
                visible: !root.isSearching && !root.isPrefixMode

                AppGridView {
                    id: appGrid
                    model: !root.isSearching ? appsModel : null
                    appsModel: root.appsModel
                    columns: root.columns
                    iconSize: root.gridIconSize
                    searchField: searchBar.field
                    showRecentApps: Plasmoid.configuration.showRecentApps !== false
                    onOriginYChanged: {
                        if (root._needsScrollToTop) {
                            contentY = originY
                            root._needsScrollToTop = false
                        }
                    }
                    onLaunched: function(index) { root.launchApp(index) }
                    onRecentLaunched: function(storageId) {
                        if (appsModel) {
                            appsModel.launchByStorageId(storageId)
                            if (appletInterface)
                                appletInterface.closeWindow()
                        }
                    }
                    onContextMenuRequested: function(index, storageId, desktopFile) {
                        contextMenu.showForApp(index, storageId, desktopFile)
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Context menu
    // -----------------------------------------------------------------------

    AppContextMenu {
        id: contextMenu
        appsModel: root.appsModel
    }

    // -----------------------------------------------------------------------
    // Animations
    // -----------------------------------------------------------------------

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: panel; property: "scale"
            from: 1.15; to: 1.0; duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: panel; property: "opacity"
            from: 0.0; to: 1.0; duration: 120
            easing.type: Easing.OutCubic
        }
        onFinished: {
            if (Plasmoid.configuration.shakeOnOpen)
                appGrid.shakeAllIcons()
        }
    }

    ParallelAnimation {
        id: closeAnim
        NumberAnimation {
            target: panel; property: "scale"
            from: 1.0; to: 1.12; duration: 120
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: panel; property: "opacity"
            from: 1.0; to: 0.0; duration: 120
            easing.type: Easing.InCubic
        }
        onFinished: {
            root.visible = false
            panel.scale = 1.15
            panel.opacity = 0.0
        }
    }
}
