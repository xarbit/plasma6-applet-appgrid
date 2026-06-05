/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for panelgeometry.js — the centered-overlay vertical offset and
    panel rect. The rect drives both the blur region and the drag input rect,
    so the centering, the offset application, and the off-screen-slack clamp
    are pinned here.
*/

import QtQuick
import QtTest
import "panelgeometry.js" as PanelGeometry

TestCase {
    name: "PanelGeometry"

    // --- verticalOffset: a fraction of the panel-to-edge slack ---

    function test_offsetCenteredIsZero() {
        // slack = (1000-600)/2 = 200; 0% → no nudge.
        compare(PanelGeometry.verticalOffset(0, 1000, 600), 0)
    }

    function test_offsetTopAndBottomReachFullSlack() {
        compare(PanelGeometry.verticalOffset(100, 1000, 600), 200)
        compare(PanelGeometry.verticalOffset(-100, 1000, 600), -200)
    }

    function test_offsetScalesWithPercent() {
        compare(PanelGeometry.verticalOffset(50, 1000, 600), 100)
    }

    function test_offsetClampsSlackWhenPanelExceedsWindow() {
        // No room to nudge → 0 regardless of percent (can't push off-screen).
        compare(PanelGeometry.verticalOffset(100, 500, 600), 0)
        compare(PanelGeometry.verticalOffset(-100, 500, 600), 0)
    }

    // --- panelRect: centered, offset + compact shift applied ---

    function test_rectCentersPanel() {
        const r = PanelGeometry.panelRect(1000, 800, 400, 300, 0, 0)
        compare(r.x, 300)   // (1000-400)/2
        compare(r.y, 250)   // (800-300)/2
        compare(r.w, 400)
        compare(r.h, 300)
    }

    function test_rectAppliesVerticalOffset() {
        const r = PanelGeometry.panelRect(1000, 800, 400, 300, 50, 0)
        compare(r.y, 300)   // 250 + 50
    }

    function test_rectAppliesCompactShift() {
        const r = PanelGeometry.panelRect(1000, 800, 400, 300, 0, 20)
        compare(r.y, 270)   // 250 + 20
    }

    function test_rectSumsOffsetAndCompactShift() {
        // Both apply additively, neither overrides the other.
        const r = PanelGeometry.panelRect(1000, 800, 400, 300, 50, 20)
        compare(r.y, 320)   // 250 + 50 + 20
    }

    function test_rectRoundsFractionalSizesAndShift() {
        const r = PanelGeometry.panelRect(1001, 800, 401, 300, 0, 15.4)
        compare(r.w, 401)
        compare(r.x, 300)   // round((1001-401)/2) = round(300)
        compare(r.y, 265)   // round((800-300)/2)=250 + round(15.4)=15
    }
}
