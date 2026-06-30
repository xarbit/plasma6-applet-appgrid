/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for VisibilityState.qml — pins the five overlapping AND
    chains that decide which child view of GridPanel is shown.
*/

import QtQuick
import QtTest

TestCase {
    name: "VisibilityState"

    function make(props) {
        var c = Qt.createComponent("VisibilityState.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, props || {})
    }

    // --- default (no flags set) ---

    function test_defaultShowsAppGridOnly() {
        var v = make()
        verify(!v.emptyHidden)
        verify(!v.catBarVisible)        // showCategoryBar input is false
        verify(!v.categorySectionsVisible)  // isSortByCategory input is false
        verify(v.appGridVisible)
        verify(!v.searchResultsVisible)
    }

    function test_defaultWithCategoryBarShowsBoth() {
        var v = make({ showCategoryBar: true })
        verify(v.catBarVisible)
        verify(v.appGridVisible)
    }

    // --- searching takes over ---

    function test_searchingHidesEverythingButSearchResults() {
        var v = make({ showCategoryBar: true, isSearching: true })
        verify(!v.catBarVisible)
        verify(!v.appGridVisible)
        verify(!v.categorySectionsVisible)
        verify(v.searchResultsVisible)
    }

    function test_searchResultsHiddenByPrefixMode() {
        // Prefix mode (e.g. ":foo") outranks search results — the
        // prefix view replaces both; the visibility object reports
        // search and grid both off.
        var v = make({ isSearching: true, isPrefixMode: true })
        verify(!v.searchResultsVisible)
        verify(!v.appGridVisible)
    }

    // --- by-category sort swaps app grid for the category grid ---

    function test_categorySortShowsCategoryGrid() {
        var v = make({ isSortByCategory: true })
        verify(v.categorySectionsVisible)
        verify(!v.appGridVisible)
    }

    function test_categorySortInFavoritesFallsBackToAppGrid() {
        // Favorites view always uses the flat app grid even under
        // by-category sort, so the user can drag-reorder freely.
        var v = make({ isSortByCategory: true, isFavoritesActive: true })
        verify(!v.categorySectionsVisible)
        verify(v.appGridVisible)
    }

    // --- folder tree (#201): folders on swaps sections for the menu tree ---

    function test_categoryFoldersSwapSectionsForTree() {
        var v = make({ isSortByCategory: true, categoryFolders: true })
        verify(v.menuFolderVisible)
        verify(!v.categorySectionsVisible)
        verify(!v.appGridVisible)
    }

    function test_selectedCategoryFoldsInAnySort() {
        // Alpha/most-used sort, a specific category tab selected → folder tree.
        var v = make({ isSortByCategory: false, categoryFolders: true, categoryFiltered: true })
        verify(v.menuFolderVisible)
        verify(!v.appGridVisible)
    }

    function test_allTabStaysFlatOutsideCategorySort() {
        // The All tab (no category filter) in a non-category sort stays flat,
        // even with folders on.
        var v = make({ isSortByCategory: false, categoryFolders: true, categoryFiltered: false })
        verify(!v.menuFolderVisible)
        verify(v.appGridVisible)
    }

    // --- hideGridWhenEmpty (compact mode) ---

    function test_compactModeHidesEverythingUntilRevealed() {
        // Compact collapse only applies to the daemon (sizeToContent).
        var v = make({ sizeToContent: true, hideGridWhenEmpty: true, showCategoryBar: true })
        verify(v.emptyHidden)
        verify(!v.catBarVisible)
        verify(!v.appGridVisible)
        verify(!v.categorySectionsVisible)
        verify(!v.searchResultsVisible)
    }

    function test_compactModeRevealedShowsGrid() {
        var v = make({
            sizeToContent: true,
            hideGridWhenEmpty: true,
            showCategoryBar: true,
            gridRevealed: true
        })
        verify(!v.emptyHidden)
        verify(v.appGridVisible)
        verify(v.catBarVisible)
    }

    function test_compactModeIgnoredInPanelVariant() {
        // The panel variant is owned by Plasma's popup sizing (sizeToContent off),
        // so hide-when-empty compact collapse stays off there even if toggled.
        var v = make({
            sizeToContent: false,
            hideGridWhenEmpty: true,
            showCategoryBar: true
        })
        verify(!v.emptyHidden)
        verify(v.appGridVisible)
    }

    function test_searchingPiercesCompactMode() {
        var v = make({ hideGridWhenEmpty: true, isSearching: true })
        verify(!v.emptyHidden)
        verify(v.searchResultsVisible)
    }
}
