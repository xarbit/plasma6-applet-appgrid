/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Thin Plasma-dialog wrapper around ConfigGeneralContent. Restores the standard
    Plasma KCM contract: a `cfg_<key>` property per setting drives Plasma's
    dirty-tracking (Apply/Cancel/Defaults) and the flush to KConfigXT (#191). The
    shared, Plasmoid-free Content writes to an injected `configuration` object —
    here a small buffer QtObject whose property names match the keys, so the
    Content is unchanged and edits stay staged until the user hits Apply/OK.
*/

import QtQuick

import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

import "../js/constants.js" as Const

KCM.SimpleKCM {
    id: page

    // Plasma reads/writes these and tracks dirty; defaults come from main.xml.
    property alias cfg_gridColumns: buffer.gridColumns
    property alias cfg_gridRows: buffer.gridRows
    property alias cfg_iconSize: buffer.iconSize
    property alias cfg_sortMode: buffer.sortMode
    property alias cfg_categoryBarDisplay: buffer.categoryBarDisplay
    property alias cfg_showCategoryBar: buffer.showCategoryBar
    property alias cfg_startWithFavorites: buffer.startWithFavorites
    property alias cfg_sortFavoritesAlphabetically: buffer.sortFavoritesAlphabetically
    property alias cfg_showRecentApps: buffer.showRecentApps
    property alias cfg_useSystemCategories: buffer.useSystemCategories
    property alias cfg_categoryFoldersEnabled: buffer.categoryFoldersEnabled
    property alias cfg_hideEmptyCategories: buffer.hideEmptyCategories
    property alias cfg_openCategoryOnHover: buffer.openCategoryOnHover
    property alias cfg_openOnActiveScreen: buffer.openOnActiveScreen
    property alias cfg_verticalOffset: buffer.verticalOffset
    property alias cfg_terminalShell: buffer.terminalShell
    property alias cfg_checkForUpdates: buffer.checkForUpdates
    // Launcher button appearance (shown on this page for both variants).
    property alias cfg_icon: buffer.icon
    property alias cfg_customButtonImage: buffer.customButtonImage
    property alias cfg_useCustomButtonImage: buffer.useCustomButtonImage
    property alias cfg_menuLabel: buffer.menuLabel

    QtObject {
        id: buffer
        property int gridColumns
        property int gridRows
        property int iconSize
        property int sortMode
        property int categoryBarDisplay
        property bool showCategoryBar
        property bool startWithFavorites
        property bool sortFavoritesAlphabetically
        property bool showRecentApps
        property bool useSystemCategories
        property bool categoryFoldersEnabled
        property bool hideEmptyCategories
        property bool openCategoryOnHover
        property bool openOnActiveScreen
        property int verticalOffset
        property string terminalShell
        property bool checkForUpdates
        property string icon
        property url customButtonImage
        property bool useCustomButtonImage
        property string menuLabel
    }

    ConfigGeneralContent {
        configuration: buffer
        isPanel: Plasmoid.pluginName === Const.PLUGIN_ID_PANEL
        formFactor: Plasmoid.formFactor
        location: Plasmoid.location
        availableShells: Plasmoid.controller.availableShells ? Plasmoid.controller.availableShells() : []
        isUniversalBuild: Plasmoid.controller.isUniversalBuild
        defaultIcon: Const.PLUGIN_ID_CENTER
    }
}
