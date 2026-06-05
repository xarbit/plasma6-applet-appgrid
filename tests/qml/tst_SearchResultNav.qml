/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for search-result navigation while SearchBar owns focus.
*/

import QtQuick
import QtTest
import "searchresultnav.js" as SearchResultNav

TestCase {
    name: "SearchResultNav"

    function test_upAtTopStaysOnTop() {
        compare(SearchResultNav.nextIndex(0, 5, -1, false), 0)
    }

    function test_downSkipsTopRow() {
        compare(SearchResultNav.nextIndex(0, 5, 1, false), 1)
    }

    function test_downClampsAtBottom() {
        compare(SearchResultNav.nextIndex(4, 5, 1, false), 4)
    }

    function test_tabWrapsAtBottom() {
        compare(SearchResultNav.nextIndex(4, 5, 1, true), 0)
    }

    // Up from the top with wrap on jumps to the last result (the wrap arm of
    // the step<0 branch — the only nextIndex branch left uncovered).
    function test_upWrapsToBottom() {
        compare(SearchResultNav.nextIndex(0, 5, -1, true), 4)
    }

    function test_singleResultStaysSelected() {
        compare(SearchResultNav.nextIndex(0, 1, 1, false), 0)
        compare(SearchResultNav.nextIndex(0, 1, -1, false), 0)
        compare(SearchResultNav.nextIndex(0, 1, 1, true), 0)
    }

    function test_emptyListReturnsNoIndex() {
        compare(SearchResultNav.nextIndex(0, 0, 1, false), -1)
        compare(SearchResultNav.nextIndex(-1, 0, -1, false), -1)
    }

    function test_noSelectionDownGoesToFirstAdvance() {
        // currentIndex -1 (nothing selected) clamps to 0, Down skips the top → 1
        compare(SearchResultNav.nextIndex(-1, 5, 1, false), 1)
    }

    function test_noSelectionUpStaysAtTop() {
        compare(SearchResultNav.nextIndex(-1, 5, -1, false), 0)
    }
}
