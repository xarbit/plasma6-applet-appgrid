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

    property bool nativePopup: false
    property bool hideGridWhenEmpty: false
    property bool showCategoryBar: false
    property bool isSearching: false
    property bool isPrefixMode: false
    property bool isFavoritesActive: false
    property bool isSortByCategory: false

    // Mutable: lets the user pop the compact-mode grid open without
    // typing (Down arrow from the search bar, wheel-down). Falls back
    // to false on reset, on a new search session, or when the user
    // wheels up while the grid is revealed.
    property bool gridRevealed: false

    // --- Outputs (consumers bind to these) ---

    // True while compact mode is hiding the grid and category bar —
    // user has not yet typed and has not popped the grid open.
    readonly property bool emptyHidden: !nativePopup
                                        && hideGridWhenEmpty
                                        && !isSearching
                                        && !isPrefixMode
                                        && !gridRevealed

    readonly property bool catBarVisible: showCategoryBar
                                          && !isSearching
                                          && !isPrefixMode
                                          && !emptyHidden

    readonly property bool categoryGridVisible: isSortByCategory
                                                && !isFavoritesActive
                                                && !isSearching
                                                && !isPrefixMode
                                                && !emptyHidden

    readonly property bool appGridVisible: !isSearching
                                           && !isPrefixMode
                                           && !categoryGridVisible
                                           && !emptyHidden

    readonly property bool searchResultsVisible: isSearching && !isPrefixMode
}
