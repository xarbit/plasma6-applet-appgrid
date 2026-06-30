/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Visibility-state machine for GridPanel's main child views.
    Inputs are the live config / search / favorites flags; outputs
    are the booleans each consumer (`visible:` bindings, layout
    branches) reads. Splitting this out of GridPanel makes the
    five overlapping AND chains testable in isolation and keeps
    GridPanel free of the flag-juggling that used to live inline.
*/

import QtQuick

QtObject {
    // --- Inputs (set by GridPanel) ---

    // The daemon sizes its window from the panel, so it supports compact collapse;
    // the panel variant is owned by Plasma's popup sizing and does not.
    property bool sizeToContent: false
    property bool hideGridWhenEmpty: false
    property bool showCategoryBar: false
    property bool isSearching: false
    property bool isPrefixMode: false
    property bool isFavoritesActive: false
    property bool isSortByCategory: false
    // System categories + the folders toggle: a category is shown as the kmenuedit
    // folder tree instead of flat sections / a flat filtered grid (issue #201).
    property bool categoryFolders: false
    // A specific category tab is selected (not All / favourites).
    property bool categoryFiltered: false

    // Mutable: lets the user pop the compact-mode grid open without
    // typing (Down arrow from the search bar, wheel-down). Falls back
    // to false on reset, on a new search session, or when the user
    // wheels up while the grid is revealed.
    property bool gridRevealed: false

    // --- Outputs (consumers bind to these) ---

    // True while compact mode is hiding the grid and category bar —
    // user has not yet typed and has not popped the grid open.
    readonly property bool emptyHidden: sizeToContent
                                        && hideGridWhenEmpty
                                        && !isSearching
                                        && !isPrefixMode
                                        && !gridRevealed

    readonly property bool catBarVisible: showCategoryBar
                                          && !isSearching
                                          && !isPrefixMode
                                          && !emptyHidden

    // Common gate: a grid is showable (not favourites / search / prefix / hidden).
    readonly property bool _gridShowable: !isFavoritesActive
                                          && !isSearching
                                          && !isPrefixMode
                                          && !emptyHidden

    // The kmenuedit folder tree: with folders on, it covers By Category (rooted at
    // all categories) AND any selected category tab in any sort — except All in a
    // non-category sort, which stays a flat grid (#201).
    readonly property bool menuFolderVisible: _gridShowable && categoryFolders
                                              && (isSortByCategory || categoryFiltered)

    // Flat category sections: By Category sort with folders off.
    readonly property bool categorySectionsVisible: _gridShowable && isSortByCategory && !categoryFolders

    readonly property bool appGridVisible: !isSearching
                                           && !isPrefixMode
                                           && !menuFolderVisible
                                           && !categorySectionsVisible
                                           && !emptyHidden

    readonly property bool searchResultsVisible: isSearching && !isPrefixMode
}
