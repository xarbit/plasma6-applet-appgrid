/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for IconShuffle.qml: a shuffle swaps two visible icons, at once
    without an overlay or once the overlay's flight lands, and clear() undoes
    every swap.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/controllers"

TestCase {
    id: testCase
    name: "IconShuffle"
    width: 200
    height: 200

    Item { id: cellA; width: 50; height: 50 }
    Item { id: cellB; x: 60; width: 50; height: 50 }

    QtObject {
        id: gridStub
        property int count: 2
        property real contentX: 0
        property real contentY: 0
        property real width: 200
        property real height: 200
        property var cellStyle: ({ iconSize: 32 })
        property var appsModel: ({ get: i => ({ iconName: i === 0 ? "kate" : "gimp" }) })
        function indexAt(x, y) { return -1 }
        function itemAtIndex(i) { return i === 0 ? cellA : i === 1 ? cellB : null }
    }

    Item {
        id: overlayStub
        property var flights: []
        signal swapFinished(int fromIndex, int toIndex, string fromIcon, string toIcon)
        function startAnim(fx, fy, tx, ty, fromIcon, toIcon, fromIndex, toIndex) {
            flights.push([fromIndex, toIndex, fromIcon, toIcon])
        }
    }

    Component {
        id: shuffleComponent
        IconShuffle { grid: gridStub }
    }

    function test_swapsAtOnceWithoutAnOverlay() {
        var s = createTemporaryObject(shuffleComponent, testCase)
        s.shuffle(0)
        compare(s.iconAt(0), "gimp")
        compare(s.iconAt(1), "kate")
        s.shuffle(0)
        compare(s.iconAt(0), "kate", "a second shuffle swaps the shown icons back")
        s.clear()
        compare(s.iconAt(0), "")
        compare(s.iconAt(1), "")
    }

    function test_overlayFlightLandsTheSwap() {
        overlayStub.flights = []
        var s = createTemporaryObject(shuffleComponent, testCase, { overlay: overlayStub })
        s.shuffle(1)
        compare(overlayStub.flights.length, 1)
        compare(s.iconAt(1), "", "nothing swapped while flying")
        const f = overlayStub.flights[0]
        overlayStub.swapFinished(f[0], f[1], f[2], f[3])
        compare(s.iconAt(1), "kate")
        compare(s.iconAt(0), "gimp")
    }

    function test_nothingToSwapWith() {
        gridStub.count = 1
        var s = createTemporaryObject(shuffleComponent, testCase)
        s.shuffle(0)
        compare(s.iconAt(0), "")
        gridStub.count = 2
    }
}
