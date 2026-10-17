/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coordinates the temporary filter relaxation that runs while the
    user is searching. With "Search across all apps" on, typing a
    query clears the active category + favorites filter so results
    aren't constrained to the current view; clearing the query
    restores whatever filter was active before. Lives here instead
    of inside SearchBar so SearchBar stops reaching across into
    panel.appsModel / categoryBar to do the swap.
*/

import QtQuick

QtObject {
    id: session

    // --- Inputs (bound by GridPanel) ---

    property var appsModel: null
    property Item categoryBar: null
    property bool searchAll: true
    property bool isPrefixMode: false

    // --- Internal save/restore state ---

    property string _savedCategory: ""
    property bool _savedFavorites: false
    property bool _filtersCleared: false

    // Called by SearchBar on every text change. Swaps the model's
    // filters when search starts and restores them when search ends.
    // Also pushes the search text into the model (or clears it in
    // prefix mode). No-op for the runner debounce / KRunner side —
    // SearchBar still owns that.
    function update(text) {
        const searching = text.length > 0 && !isPrefixMode
        let category = appsModel ? appsModel.filterCategory : ""
        let favorites = appsModel ? appsModel.showFavoritesOnly : false
        let restoreFavoritesTab = false

        if (searching && searchAll && !_filtersCleared) {
            _savedCategory = category
            _savedFavorites = categoryBar ? categoryBar.favoritesActive : false
            category = ""
            favorites = false
            _filtersCleared = true
        } else if (!searching && _filtersCleared) {
            category = _savedCategory
            favorites = _savedFavorites
            restoreFavoritesTab = true
            _filtersCleared = false
        }

        // Text, category and favourites change together on a search start or
        // end: hand them over in one call so the model filters once.
        if (appsModel)
            appsModel.setSearchState(isPrefixMode ? "" : text, category, favorites)
        if (restoreFavoritesTab && categoryBar)
            categoryBar.favoritesActive = _savedFavorites
    }
}
