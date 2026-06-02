/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Switcher for prefix mode views: help, terminal, command, files, info, hidden.
    Each mode is implemented in its own component under prefix/.
*/

import QtQuick

import "../prefix" as Prefix
import "../js/prefixmodes.js" as PrefixModes

Item {
    id: prefixView

    property string mode: ""
    property string argument: ""
    property Item searchField: null
    property var sharedFavoritesModel: null
    required property bool showScrollbars

    // Per-mode dependencies, forwarded to the individual prefix views.
    required property var appsModel
    required property var listDirectory
    required property var sysInfo
    required property var updateChecker
    required property bool favoritesPortedToKAstats
    required property list<string> favoriteApps
    required property var markUnported

    signal fileOpened()
    signal directoryNavigated(string path)

    function focusFileList() { fileBrowser.focusList() }
    function activateFileCurrent() { fileBrowser.activateCurrent() }

    // -- Help --
    Prefix.PrefixHelpView {
        anchors.fill: parent
        visible: prefixView.mode === PrefixModes.HELP
        showScrollbars: prefixView.showScrollbars
    }

    // -- Terminal / Command --
    Prefix.PrefixCommandView {
        mode: prefixView.mode
        argument: prefixView.argument
        visible: prefixView.mode === PrefixModes.TERMINAL || prefixView.mode === PrefixModes.COMMAND
    }

    // -- System info --
    Prefix.PrefixInfoView {
        anchors.fill: parent
        visible: prefixView.mode === PrefixModes.INFO
        sharedFavoritesModel: prefixView.sharedFavoritesModel
        showScrollbars: prefixView.showScrollbars
        sysInfo: prefixView.sysInfo
        updateChecker: prefixView.updateChecker
        favoritesPortedToKAstats: prefixView.favoritesPortedToKAstats
        favoriteApps: prefixView.favoriteApps
        markUnported: prefixView.markUnported
    }

    // -- Hidden apps --
    Prefix.PrefixHiddenView {
        anchors.fill: parent
        visible: prefixView.mode === PrefixModes.HIDDEN
        appsModel: prefixView.appsModel
    }

    // -- File browser --
    Prefix.PrefixFileBrowser {
        id: fileBrowser
        anchors.fill: parent
        visible: prefixView.mode === PrefixModes.FILES
        path: prefixView.argument
        searchField: prefixView.searchField
        listDirectory: prefixView.listDirectory
        onFileOpened: prefixView.fileOpened()
        onDirectoryNavigated: function(path) { prefixView.directoryNavigated(path) }
    }
}
