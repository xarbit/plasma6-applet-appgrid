/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for SelectionState.qml — the multi-selection state object
    shared by the grid views. Tests pin the Ctrl/Shift+click, range,
    select-all, and Shift+Arrow extend flows that AppIconDelegate and
    the keyboard navigation helpers rely on.
*/

import QtQuick
import QtTest

TestCase {
    name: "SelectionState"

    // Build a SelectionState with a deterministic sid mapping
    // (index N → "appN.desktop") and the given grid size.
    function makeSelection(count) {
        var c = Qt.createComponent("SelectionState.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        return c.createObject(null, {
            gridCount: count,
            sidAt: function(idx) {
                return (idx >= 0 && idx < count) ? "app" + idx + ".desktop" : ""
            }
        })
    }

    // Fake QMouseEvent.modifiers for applyModClick().
    function mouseWith(mods) { return { modifiers: mods } }

    // --- toggle ---

    function test_toggleAtAddsAndSetsAnchor() {
        var s = makeSelection(5)
        s.toggleAt(2)
        verify(s.contains("app2.desktop"))
        compare(s.selectionCount, 1)
        compare(s.anchor, 2)
    }

    function test_toggleAtTwiceRemoves() {
        var s = makeSelection(5)
        s.toggleAt(2)
        s.toggleAt(2)
        verify(!s.contains("app2.desktop"))
        compare(s.selectionCount, 0)
        compare(s.anchor, 2)
    }

    function test_sidListReflectsState() {
        var s = makeSelection(5)
        s.toggleAt(1)
        s.toggleAt(3)
        var list = s.sidList()
        list.sort()
        compare(list, ["app1.desktop", "app3.desktop"])
    }

    // Direct sid toggle with anchorIdx -1 adds the sid but leaves the anchor
    // where the last indexed toggle put it (the right-click "add to selection"
    // path, which has no grid index).
    function test_toggleSidKeepsAnchorWhenNoIndex() {
        var s = makeSelection(5)
        s.toggleAt(2)               // anchor = 2
        s.toggleSid("extra.desktop", -1)
        verify(s.contains("extra.desktop"))
        compare(s.selectionCount, 2)
        compare(s.anchor, 2)        // unchanged
    }

    // A range that overlaps already-selected items counts each app once.
    function test_rangeToWithOverlapDoesNotDoubleCount() {
        var s = makeSelection(5)
        s.toggleAt(0)               // app0 selected, anchor 0
        s.rangeTo(2)                // 0..2; app0 already in
        compare(s.selectionCount, 3)
        verify(s.contains("app0.desktop"))
        verify(s.contains("app1.desktop"))
        verify(s.contains("app2.desktop"))
    }

    // --- rangeTo ---

    function test_rangeToExtendsForward() {
        var s = makeSelection(10)
        s.toggleAt(2)               // anchor = 2
        s.rangeTo(5)                // selects 2..5 inclusive
        compare(s.selectionCount, 4)
        verify(s.contains("app2.desktop"))
        verify(s.contains("app3.desktop"))
        verify(s.contains("app4.desktop"))
        verify(s.contains("app5.desktop"))
    }

    function test_rangeToExtendsBackwardFromAnchor() {
        var s = makeSelection(10)
        s.toggleAt(5)               // anchor = 5
        s.rangeTo(2)                // selects 2..5
        compare(s.selectionCount, 4)
        // Anchor stays put — rangeTo never moves it.
        compare(s.anchor, 5)
    }

    function test_rangeToFallsBackToToggleWhenNoAnchor() {
        var s = makeSelection(5)
        // No prior toggle → anchor < 0 → behaves as toggleAt.
        s.rangeTo(2)
        verify(s.contains("app2.desktop"))
        compare(s.anchor, 2)
    }

    function test_rangeToIgnoresOutOfBoundsIndex() {
        var s = makeSelection(5)
        s.toggleAt(0)
        s.rangeTo(99)
        compare(s.selectionCount, 1) // unchanged
    }

    // --- selectAll ---

    function test_selectAllPicksEveryItem() {
        var s = makeSelection(4)
        s.selectAll(2)
        compare(s.selectionCount, 4)
        compare(s.anchor, 2)
    }

    function test_selectAllKeepsExistingAnchor() {
        var s = makeSelection(4)
        s.toggleAt(1)                // anchor = 1
        s.selectAll(3)               // anchor already set, don't overwrite
        compare(s.anchor, 1)
    }

    function test_selectAllDefaultsAnchorToZeroWhenCallerHasNone() {
        var s = makeSelection(4)
        s.selectAll(-1)
        compare(s.anchor, 0)
    }

    // --- clear / consumeEscape ---

    function test_clearResetsEverything() {
        var s = makeSelection(5)
        s.toggleAt(0)
        s.toggleAt(2)
        s.clear()
        compare(s.selectionCount, 0)
        compare(s.anchor, -1)
        verify(!s.contains("app0.desktop"))
    }

    function test_consumeEscapeFalseWhenEmpty() {
        var s = makeSelection(5)
        verify(!s.consumeEscape())
    }

    function test_consumeEscapeTrueAndClearsWhenActive() {
        var s = makeSelection(5)
        s.toggleAt(2)
        verify(s.consumeEscape())
        compare(s.selectionCount, 0)
        compare(s.anchor, -1)
    }

    // --- applyModClick ---

    function test_applyModClickPlainClickFallsThrough() {
        var s = makeSelection(5)
        verify(!s.applyModClick(mouseWith(Qt.NoModifier), 1))
        compare(s.selectionCount, 0)
    }

    function test_applyModClickCtrlTogglesAt() {
        var s = makeSelection(5)
        verify(s.applyModClick(mouseWith(Qt.ControlModifier), 1))
        verify(s.contains("app1.desktop"))
    }

    function test_applyModClickShiftRangesToAnchor() {
        var s = makeSelection(10)
        s.toggleAt(2)
        verify(s.applyModClick(mouseWith(Qt.ShiftModifier), 5))
        compare(s.selectionCount, 4) // 2..5
    }

    // --- extendOrMove (Shift+Arrow) ---

    function test_extendOrMovePlainArrowJustMoves() {
        var s = makeSelection(5)
        var cursor = 2
        s.extendOrMove({ modifiers: Qt.NoModifier },
                       function() { cursor++ },
                       function() { return cursor })
        compare(cursor, 3)
        compare(s.selectionCount, 0)
        compare(s.anchor, -1)
    }

    function test_extendOrMoveShiftSetsAnchorOnFirstUse() {
        var s = makeSelection(5)
        var cursor = 1
        s.extendOrMove({ modifiers: Qt.ShiftModifier },
                       function() { cursor++ },
                       function() { return cursor })
        // Anchor latched to the pre-move cursor (1); range extends to 2.
        compare(s.anchor, 1)
        verify(s.contains("app1.desktop"))
        verify(s.contains("app2.desktop"))
    }

    function test_extendOrMoveShiftKeepsAnchorAndGrowsRange() {
        var s = makeSelection(10)
        s.toggleAt(2)                  // anchor = 2
        var cursor = 2
        // Walk three steps forward with Shift held.
        for (var i = 0; i < 3; ++i) {
            s.extendOrMove({ modifiers: Qt.ShiftModifier },
                           function() { cursor++ },
                           function() { return cursor })
        }
        compare(cursor, 5)
        compare(s.anchor, 2)
        compare(s.selectionCount, 4) // 2..5
    }

    // --- model-backed helpers ---

    function test_desktopFileUrlsResolveThroughModel() {
        var s = makeSelection(5)
        s.toggleAt(1)
        s.toggleAt(3)
        var model = {
            getByStorageId: function(sid) {
                return { desktopFile: "/path/" + sid }
            }
        }
        var urls = s.desktopFileUrls(model)
        urls.sort()
        compare(urls, ["file:///path/app1.desktop",
                       "file:///path/app3.desktop"])
    }

    function test_iconNamesResolveThroughModel() {
        var s = makeSelection(5)
        s.toggleAt(0)
        var model = {
            getByStorageId: function(sid) {
                return { iconName: sid.replace(".desktop", "-icon") }
            }
        }
        compare(s.iconNames(model), ["app0-icon"])
    }

    // --- unified index space (recents + grid) ---
    //
    // The grids feed SelectionState a `sidAt` that maps low indices to
    // the recents row and high indices to the actual grid. Range fill
    // must walk the boundary so Shift+Arrow from grid into recents
    // (or vice versa) extends the selection through both sides.

    function test_rangeAcrossUnifiedDomainSelectsBothSides() {
        var c = Qt.createComponent("SelectionState.qml")
        verify(c.status === Component.Ready, "component error: " + c.errorString())
        // 0..2 are recents, 3..7 are grid.
        var s = c.createObject(null, {
            gridCount: 8,
            sidAt: function(idx) {
                if (idx < 0 || idx >= 8) return ""
                return (idx < 3 ? "recent" : "grid") + idx + ".desktop"
            }
        })

        s.toggleAt(3)               // anchor on the first grid cell
        s.rangeTo(0)                // walk back through every recents cell

        compare(s.selectionCount, 4)
        verify(s.contains("grid3.desktop"))
        verify(s.contains("recent2.desktop"))
        verify(s.contains("recent1.desktop"))
        verify(s.contains("recent0.desktop"))
    }

    function test_modelHelpersReturnEmptyOnNullModel() {
        var s = makeSelection(5)
        s.toggleAt(0)
        compare(s.desktopFileUrls(null), [])
        compare(s.iconNames(null), [])
    }
}
