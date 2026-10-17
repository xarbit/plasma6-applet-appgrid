/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for GridSelection.qml: the recents row and the grid share one
    index space, grid indices are offset past the recents, and nothing is
    selected while the grid has multi-selection off.
*/

import QtQuick
import QtTest

TestCase {
    name: "GridSelection"

    QtObject {
        id: appsStub
        property var recentApps: ["r0", "r1"]
        function getByStorageId(sid) { return ({ desktopFile: "/apps/" + sid + ".desktop", iconName: sid + "-icon" }) }
    }

    function make(props) {
        var c = Qt.createComponent("../../package/contents/ui/controllers/GridSelection.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        var p = { active: true, appsModel: appsStub, recentCount: 2, itemCount: 3,
                  gridSidAt: function(i) { return ["g0", "g1", "g2"][i] || "" } }
        for (var k in props || {}) p[k] = props[k]
        return createTemporaryObject(c, null, p)
    }

    function test_sharedIndexSpace() {
        var s = make()
        compare(s.gridCount, 5)
        compare(s.sidAt(0), "r0")
        compare(s.sidAt(2), "g0")
        compare(s.sidAt(4), "g2")
        compare(s.sidAt(-1), "")
    }

    function test_gridIndicesAreOffset() {
        var s = make()
        s.toggleSelectionAt(1)
        compare(s.sidList().join(","), "g1")
        compare(s.anchor, 3)
        s.rangeSelectTo(2)
        compare(s.sidList().sort().join(","), "g1,g2")
    }

    function test_virtualIndexFollowsTheCursor() {
        var s = make({ recentIndex: 1 })
        compare(s.virtualIndex, 1)
        s.recentIndex = -1
        s.currentIndex = 2
        compare(s.virtualIndex, 4)
        s.currentIndex = -1
        compare(s.virtualIndex, -1)
    }

    function test_selectAllSpansRecentsAndGrid() {
        var s = make({ currentIndex: 0 })
        s.selectAllVisible()
        compare(s.selectionCount, 5)
        compare(s.selectedDesktopFileUrls().length, 5)
        compare(s.selectedIconNames()[0].indexOf("-icon") > 0, true)
    }

    function test_inactiveSelectsNothing() {
        var s = make({ active: false })
        s.toggleSelectionAt(0)
        s.toggleSelectionBySid("g1")
        s.selectAllVisible()
        verify(!s.applyClickModifiers({ modifiers: Qt.ControlModifier }, 0))
        compare(s.selectionCount, 0)
    }

    function test_modifierClicks() {
        var s = make()
        verify(s.applyClickModifiers({ modifiers: Qt.ControlModifier }, 0))
        verify(s.applyRecentClickModifiers({ modifiers: Qt.ControlModifier }, 1))
        compare(s.sidList().sort().join(","), "g0,r1")
        verify(!s.applyClickModifiers({ modifiers: Qt.NoModifier }, 2))
    }
}
