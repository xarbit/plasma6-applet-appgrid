/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    What the launcher's grids (the app grid, the By Category sections and the
    menu folders) share with the panel that hosts them: the models and objects
    they read, and the requests they make of it. The panel builds one and
    handles each request once; a grid takes the host instead of having each
    of these passed and each of its requests forwarded by hand.
*/

import QtQuick

QtObject {
    // --- What the grids read ---

    // AppFilterModel: the apps, their categories, recents and badges.
    property var appsModel: null
    // FavoritesManager: favourites and their folders.
    property var favoritesManager: null
    // The controller's LaunchStateStore: recents, hidden apps, launch counts.
    property var launchState: null
    // The DragSource of the launcher's own drags; null disables dragging.
    property var dragSource: null
    // The search field, where focus returns when the user starts typing.
    property Item searchField: null
    // How the cells draw (CellStyle).
    property var cellStyle: null
    // Columns of a grid that doesn't fit its own.
    property int columns: 5

    // --- What the grids ask for ---

    // Launch the app at @p index of appsModel.
    signal launchAppRequested(int index)
    // Launch @p storageId: an app, a jump-list action, a favourite.
    signal launchRequested(string storageId)
    // Launch several apps at once (Enter on a multi-selection).
    signal bulkLaunchRequested(var sids)
    // Alt+Left / Alt+Right: the previous or next category.
    signal categoryNavRequested(int direction)
    // The app menu for @p storageId, with the grid's selection.
    signal appMenuRequested(string storageId, string desktopFile, var selectedSids)
}
