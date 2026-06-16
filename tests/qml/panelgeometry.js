/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Centered-overlay panel geometry. The vertical nudge and the panel rect were
    inline in GridWindow, but the rect feeds two consumers — the blur/contrast
    region and the drag-out input rect — so a drift would silently break one of
    them. Pure here (screen + panel sizes in, geometry out) and under test.
*/

.pragma library
.import "devicepixels.js" as DevicePixels

// User vertical nudge for the centered panel. percent ∈ [-100, 100] is a
// fraction of the slack between the full panel and the screen edge, so it
// scales across screen sizes and can never push the panel off-screen. Pass the
// full panel height (not the animating height) so the compact-mode height
// animation doesn't drag the panel up or down as it expands.
function verticalOffset(percent, windowHeight, panelHeight) {
    const slack = Math.max(0, (windowHeight - panelHeight) / 2)
    return Math.round(percent / 100 * slack)
}

// Geometry of the centered panel within the overlay window, including the user
// vertical offset and the compact-mode downward shift. Shared by the blur
// region, the drag input rect and the panel's own placement — keep it the single
// source so the three never drift.
//
// Size and position are snapped to the device-pixel grid for @p dpr so the
// panel's painted edges and the blur region round to the same device pixels
// under fractional scaling (see devicepixels.js). dpr defaults to 1 (no
// fractional scaling), where snapping is plain integer rounding — the prior
// behaviour.
function panelRect(windowWidth, windowHeight, panelWidth, panelHeight, vOffset, compactShift, dpr) {
    const ratio = dpr > 0 ? dpr : 1
    const w = DevicePixels.snap(panelWidth, ratio)
    const h = DevicePixels.snap(panelHeight, ratio)
    return {
        x: DevicePixels.snap((windowWidth - w) / 2, ratio),
        y: DevicePixels.snap((windowHeight - h) / 2 + vOffset + compactShift, ratio),
        w: w,
        h: h,
    }
}
