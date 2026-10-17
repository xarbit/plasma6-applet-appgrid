/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Open-on-hover for the category bar (#176): dwelling on a tab selects it
    without a click. HoverActivation owns the armed tab (and the
    enter-before-leave race); this adds the timing around it:

      * a dwell before a hovered tab selects;
      * a wheel scroll slides tabs under a still cursor, so hover-select is
        suppressed (and the highlight dropped) until the scroll settles, then
        the tab under the cursor is selected once;
      * entering the bar is treated the same, so a cursor merely crossing it
        selects nothing; leaving the bar cancels everything in flight.

    The tabs report enter / leave; the bar reports wheel and bar crossings
    and answers tabUnderPointer().
*/

import QtQuick
import org.kde.kirigami as Kirigami

QtObject {
    id: root

    property bool enabled: false
    // () -> the tab id under the pointer, or "".
    property var tabUnderPointer: function() { return "" }

    // Dwell before a hovered tab selects.
    readonly property int dwell: 5
    // Dwell before a hovered scroll arrow pages, so sweeping the cursor across
    // it doesn't page; floored at 150ms so it still works with animations off.
    readonly property int pageDwell: Math.max(Kirigami.Units.shortDuration * 3, 150)
    // While the cursor rests on a scroll arrow it keeps paging, but only this
    // often — slow enough that a resting cursor doesn't race to the end.
    readonly property int pageRepeat: 800
    // One window governs a whole wheel interaction: until this long after the
    // last wheel event, hover-select stays suppressed and the highlight stays
    // dropped. Must exceed the gap between wheel notches so a multi-notch
    // scroll doesn't settle mid-way.
    readonly property int wheelGrace: Math.max(Kirigami.Units.longDuration, 300)
    // A wheel scroll is in progress: the tabs drop their highlight until it
    // settles. Visual only; the grid filter is left alone so it doesn't flash.
    property bool wheelScrolling: false

    signal selectRequested(string tabId)

    function enter(tabId) {
        if (_activation.enter(tabId))
            _dwellTimer.restart()
    }

    function leave(tabId) {
        if (_activation.leave(tabId))
            _dwellTimer.stop()
    }

    function wheel() {
        _activation.suppress()
        _dwellTimer.stop()
        if (!enabled)
            return
        wheelScrolling = true
        _settleTimer.restart()
    }

    // The pointer entered (@p inside) or left the bar.
    function crossBar(inside) {
        if (!enabled)
            return
        if (inside) {
            _activation.suppress()
            _settleTimer.restart()
        } else {
            _activation.clear()
            _dwellTimer.stop()
            _settleTimer.stop()
        }
    }

    property HoverActivation _activation: HoverActivation {
        enabled: root.enabled
        wheelGraceMs: root.wheelGrace
    }

    property Timer _dwellTimer: Timer {
        interval: root.dwell
        onTriggered: {
            if (root._activation.pending !== "")
                root.selectRequested(root._activation.pending)
        }
    }

    // Once a suppression window (wheel or bar entry) passes with the cursor
    // still, nothing re-arms on its own: restore the highlight, then select
    // whatever tab is under the pointer so it ends up the single highlighted one.
    property Timer _settleTimer: Timer {
        interval: root.wheelGrace
        onTriggered: {
            root.wheelScrolling = false
            if (!root.enabled)
                return
            const tabId = root.tabUnderPointer()
            if (tabId !== "")
                root.selectRequested(tabId)
        }
    }
}
