/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for CellHighlight.qml: built only while shown, one look per kind.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/widgets"

TestCase {
    id: testCase
    name: "CellHighlight"
    width: 100
    height: 100
    when: windowShown

    Component {
        id: cell
        Item {
            width: 100
            height: 100
            property alias highlight: highlight
            CellHighlight { id: highlight }
        }
    }

    function test_builtOnlyWhileShown() {
        var c = createTemporaryObject(cell, testCase)
        compare(c.highlight.item, null)
        c.highlight.shown = true
        verify(c.highlight.item)
        verify(c.highlight.item.width < 100, "inset from the cell")
        c.highlight.shown = false
        compare(c.highlight.item, null)
    }

    function test_kindsDiffer() {
        var c = createTemporaryObject(cell, testCase)
        c.highlight.shown = true
        c.highlight.kind = CellHighlight.Hover
        compare(c.highlight.item.border.width, 0)
        c.highlight.kind = CellHighlight.Selected
        compare(c.highlight.item.border.width, 1)
        c.highlight.kind = CellHighlight.Anchor
        compare(c.highlight.item.border.width, 2)
        const anchorBorder = c.highlight.item.border.color.toString()
        c.highlight.kind = CellHighlight.FoldTarget
        compare(c.highlight.item.border.width, 2)
        verify(c.highlight.item.border.color.toString() !== anchorBorder)
    }
}
