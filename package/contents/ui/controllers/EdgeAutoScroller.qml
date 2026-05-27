/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Proximity-driven edge auto-scroll for a Flickable while a drag is
    hovering near its top/bottom edge. Closer to the edge → faster scroll;
    eases in smoothly across the zone boundary (quadratic).

    Wire it up by giving it the Flickable to scroll and the DropArea whose
    `containsDrag` / `drag.y` signal the active drag:

        EdgeAutoScroller {
            id: edgeScroller
            flickable: gridView
            dropArea: reorderArea
        }

    Then `edgeScroller.active` is true while a scroll tick is firing — use
    that from the reorder code to defer move()s until the scroll settles.
*/

import QtQuick
import org.kde.kirigami as Kirigami

import "../js/scrolleasing.js" as ScrollEasing

QtObject {
    id: scroller

    required property Flickable flickable
    required property DropArea dropArea

    property real edge: Kirigami.Units.gridUnit * 2
    property real minPxPerTick: 1
    property real maxPxPerTick: Kirigami.Units.gridUnit * 0.6
    property int intervalMs: 16   // ~60 Hz

    readonly property bool scrollingUp: dropArea.enabled
        && dropArea.containsDrag
        && dropArea.drag.y >= 0
        && dropArea.drag.y < edge
        && flickable.contentY > 0

    readonly property bool scrollingDown: dropArea.enabled
        && dropArea.containsDrag
        && dropArea.drag.y > flickable.height - edge
        && dropArea.drag.y <= flickable.height
        && flickable.contentY < (flickable.contentHeight - flickable.height)

    readonly property bool active: scrollingUp || scrollingDown

    property Timer _timer: Timer {
        interval: scroller.intervalMs
        repeat: true
        running: scroller.active
        onTriggered: {
            const delta = ScrollEasing.deltaPerTick(
                scroller.scrollingUp,
                scroller.dropArea.drag.y,
                scroller.edge,
                scroller.flickable.height,
                scroller.minPxPerTick,
                scroller.maxPxPerTick)
            const dir = scroller.scrollingUp ? -1 : 1
            const max = Math.max(0,
                scroller.flickable.contentHeight - scroller.flickable.height)
            scroller.flickable.contentY = Math.max(0,
                Math.min(max, scroller.flickable.contentY + dir * delta))
        }
    }
}
