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
    readonly property bool showScrollbars: source.showScrollbars
    readonly property int verticalOffset: source.verticalOffset
    readonly property bool showTooltips: source.showTooltips
    readonly property bool hoverHighlight: source.hoverHighlight
    readonly property bool showNewAppBadge: source.showNewAppBadge
    readonly property bool iconShadow: source.iconShadow
    readonly property int iconSize: source.iconSize
    readonly property bool independentTextSize: source.independentTextSize
    readonly property bool reduceGridSpacing: source.reduceGridSpacing
    readonly property int hoverAnimation: source.hoverAnimation
    readonly property bool shakeOnOpen: source.shakeOnOpen

    // --- Grid layout ---

    readonly property int gridColumns: source.gridColumns
    readonly property int gridRows: source.gridRows
    readonly property bool showCategoryBar: source.showCategoryBar
    readonly property bool hideEmptyCategories: source.hideEmptyCategories
    readonly property bool openCategoryOnHover: source.openCategoryOnHover
    readonly property int categoryBarDisplay: source.categoryBarDisplay
    readonly property bool useSystemCategories: source.useSystemCategories
    readonly property int sortMode: source.sortMode
    readonly property bool showRecentApps: source.showRecentApps
    readonly property bool hideGridWhenEmpty: source.hideGridWhenEmpty
    readonly property bool startWithFavorites: source.startWithFavorites

    // --- Favorites ---

    readonly property bool sortFavoritesAlphabetically: source.sortFavoritesAlphabetically
    readonly property bool hideLabelsOnFavorites: source.hideLabelsOnFavorites
    readonly property bool favoriteFoldersEnabled: source.favoriteFoldersEnabled
    readonly property bool enableActivities: source.enableActivities

    // Hidden / recent / known apps and launch counts are no longer here: that
    // per-user launch state lives in the shared LaunchStateStore (appgridrc),
    // synced straight into the model by AppGridController, so every variant and
    // the daemon share one list. See src/launchstatestore.h.

    // --- Search / runners ---

    readonly property bool searchAll: source.searchAll
    readonly property bool useExtraRunners: source.useExtraRunners
    readonly property bool searchUsesFrecency: source.searchUsesFrecency
    readonly property bool searchShowsHidden: source.searchShowsHidden
    readonly property bool searchInlineCompletion: source.searchInlineCompletion
    readonly property bool showSearchShortcuts: source.showSearchShortcuts
    readonly property string terminalShell: source.terminalShell

    // --- Power / session ---

    readonly property list<string> headerActions: source.headerActions
    readonly property list<string> customHeaderActions: source.customHeaderActions
    readonly property string menuButtonIcon: source.menuButtonIcon
    readonly property bool showActionLabels: source.showActionLabels
    readonly property bool hideMenuButtonLabel: source.hideMenuButtonLabel

    // --- Update checker (universal builds) ---

    readonly property bool checkForUpdates: source.checkForUpdates
}
