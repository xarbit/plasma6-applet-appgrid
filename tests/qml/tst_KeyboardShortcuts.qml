/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for KeyboardShortcuts.qml's favourites reorder: it moves the
    highlighted entry in the grouped favourites model the grid shows, and
    does nothing for sorted favourites or outside the favourites view.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "KeyboardShortcuts"

    ListModel {
        id: groupedStub
        property var moves: []
        ListElement { name: "a" }
        ListElement { name: "b" }
        ListElement { name: "c" }
        function moveRow(from, to) {
            moves.push(from + ">" + to)
            move(from, to, 1)
        }
    }

    GridView {
        id: grid
        width: 300
        height: 100
        cellWidth: 100
        cellHeight: 100
        model: groupedStub
        delegate: Item { width: 100; height: 100 }
        property bool favoritesActive: true
        property bool groupEditable: true
        property var groupedModel: groupedStub
        property int effectiveColumns: 3
        property bool multiSelectActive: false
        property var selection: ({ selectionCount: 0, virtualIndex: -1 })
    }

    function make(sorted) {
        var c = Qt.createComponent("../../package/contents/ui/controllers/KeyboardShortcuts.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        return createTemporaryObject(c, testCase, { grid: grid, sortFavoritesAlphabetically: sorted })
    }

    function init() {
        groupedStub.moves = []
        grid.favoritesActive = true
        grid.groupEditable = true
        grid.currentIndex = 0
    }

    function test_reorderMovesInTheGroupedModel() {
        var s = make(false)
        verify(s.reorderTo(1))
        compare(groupedStub.moves.join(","), "0>1")
        compare(grid.currentIndex, 1)
        compare(groupedStub.get(1).name, "a")
    }

    function test_noReorderWhenSorted() {
        var s = make(true)
        verify(!s.reorderTo(1))
        compare(groupedStub.moves.length, 0)
    }

    function test_noReorderOutsideFavoritesOrReadOnly() {
        var s = make(false)
        grid.favoritesActive = false
        verify(!s.reorderTo(1))
        grid.favoritesActive = true
        grid.groupEditable = false
        verify(!s.reorderTo(1))
        compare(groupedStub.moves.length, 0)
    }

    function test_outOfRangeTarget() {
        var s = make(false)
        verify(!s.reorderTo(5))
        verify(!s.reorderTo(0))
        compare(groupedStub.moves.length, 0)
    }
}
