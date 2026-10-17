/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    What the launcher shows: the selected tab (Favorites, or a category, or
    All) and the applied search. The category bar displays this state and
    asks to change it; the apps model's filter follows from it in one call
    per change:

    - the favourites tab shows only favourites, a category filters the flat
      sorts (By Category scrolls to it and the folder tree roots at it
      instead, so those leave the filter empty);
    - with "Search across all apps" on, a search shows every app and the
      selection comes back when the search is cleared — the selection itself
      never changes while searching, so there is nothing to save and restore;
    - a prefix mode (t:, c:, …) pushes no search text.
*/

import QtQuick

QtObject {
    id: state

    // --- Inputs ---

    property var appsModel: null
    // "Search across all apps" (cfg.searchAll).
    property bool searchAll: true
    // The field holds a prefix-mode command, not a search.
    property bool isPrefixMode: false
    // The selected category filters the grid (flat sorts); false in By
    // Category and the folder tree, where it scrolls or roots instead.
    property bool categoryFilters: true

    // --- State ---

    property bool favorites: false
    // Empty = All.
    property string category: ""
    property string searchText: ""

    readonly property bool searching: searchText.length > 0 && !isPrefixMode

    // --- Changes ---

    // The favourites tab on or off; on also clears the category.
    function selectFavorites(active) {
        favorites = active
        if (active)
            category = ""
        _push()
    }

    // A category tab, or All for an empty @p name; leaves favourites.
    function selectCategory(name) {
        favorites = false
        category = name
        _push()
    }

    // The search the model filters with (deferred by the caller).
    function setSearchText(text) {
        searchText = text
        _push()
    }

    // Back to the start tab with no search.
    function reset(startWithFavorites) {
        favorites = startWithFavorites
        category = ""
        searchText = ""
        _push()
    }

    onCategoryFiltersChanged: _push()
    onSearchAllChanged: _push()
    onIsPrefixModeChanged: _push()

    // Text, category and favourites go to the model together, so it filters
    // once per change.
    function _push() {
        if (!appsModel)
            return
        const relaxed = searching && searchAll
        appsModel.setSearchState(isPrefixMode ? "" : searchText,
                                 relaxed || favorites || !categoryFilters ? "" : category,
                                 favorites && !relaxed)
    }
}
