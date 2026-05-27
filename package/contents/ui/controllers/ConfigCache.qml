/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Single read-side surface for the plasmoid configuration. Every
    QML consumer that needs a setting reads it through this object
    so the kcfg schema is documented in one place, the property
    types are explicit, and tests can swap `source` for a plain
    QObject stub without touching the consumers.

    Writes still go directly through Plasmoid.configuration — they
    happen in a handful of spots (recents, launchCounts, knownApps,
    the migration flags) and centralising them belongs in a separate
    pass.
*/

import QtQuick
import org.kde.plasma.plasmoid

QtObject {
    id: cache

    // The live configuration object. Production wires
    // Plasmoid.configuration once at the root; tests pass a QObject
    // stub with the same property surface.
    required property var source

    // --- General / appearance ---

    readonly property string icon: source.icon
    readonly property bool useCustomButtonImage: source.useCustomButtonImage
    readonly property url customButtonImage: source.customButtonImage
    readonly property string menuLabel: source.menuLabel
    readonly property bool openOnActiveScreen: source.openOnActiveScreen
    readonly property bool showDividers: source.showDividers
    readonly property int openAnimation: source.openAnimation
    readonly property bool showScrollbars: source.showScrollbars
    readonly property int backgroundOpacity: source.backgroundOpacity
    readonly property bool enableBlur: source.enableBlur
    readonly property bool dimBackground: source.dimBackground
    readonly property int verticalOffset: source.verticalOffset
    readonly property bool showTooltips: source.showTooltips
    readonly property bool showNewAppBadge: source.showNewAppBadge
    readonly property bool iconShadow: source.iconShadow
    readonly property bool overrideRadius: source.overrideRadius
    readonly property int cornerRadius: source.cornerRadius
    readonly property int iconSize: source.iconSize
    readonly property int hoverAnimation: source.hoverAnimation
    readonly property bool shakeOnOpen: source.shakeOnOpen

    // --- Grid layout ---

    readonly property int gridColumns: source.gridColumns
    readonly property int gridRows: source.gridRows
    readonly property bool showCategoryBar: source.showCategoryBar
    readonly property bool hideEmptyCategories: source.hideEmptyCategories
    readonly property bool useSystemCategories: source.useSystemCategories
    readonly property int sortMode: source.sortMode
    readonly property bool showRecentApps: source.showRecentApps
    readonly property bool hideGridWhenEmpty: source.hideGridWhenEmpty
    readonly property bool startWithFavorites: source.startWithFavorites

    // --- Favorites ---

    readonly property list<string> favoriteApps: source.favoriteApps
    readonly property bool sortFavoritesAlphabetically: source.sortFavoritesAlphabetically
    readonly property bool hideLabelsOnFavorites: source.hideLabelsOnFavorites
    readonly property bool favoritesPortedToKAstats: source.favoritesPortedToKAstats

    // --- App state (mutated by the panel; read-only here) ---

    readonly property list<string> hiddenApps: source.hiddenApps
    readonly property list<string> recentApps: source.recentApps
    readonly property list<string> knownApps: source.knownApps
    readonly property list<string> launchCounts: source.launchCounts

    // --- Search / runners ---

    readonly property bool searchAll: source.searchAll
    readonly property bool useExtraRunners: source.useExtraRunners
    readonly property string terminalShell: source.terminalShell

    // --- Power / session ---

    readonly property list<string> powerButtonOrder: source.powerButtonOrder
    readonly property list<string> powerButtonsHidden: source.powerButtonsHidden
    readonly property bool showActionLabels: source.showActionLabels

    // --- Update checker (universal builds) ---

    readonly property bool checkForUpdates: source.checkForUpdates
}
