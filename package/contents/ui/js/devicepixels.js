/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Device-pixel grid helpers for fractional scaling.

    The compositor rasterizes the KWin blur/contrast region (specified in logical
    pixels) and the Qt scene graph rasterizes the panel art independently. At a
    fractional scale a logical edge that is not on the device-pixel grid rounds to
    different device pixels in the two pipelines, so a frosted panel's straight
    edges show a ~1px seam. A compositor-placed window avoids this for free
    because its geometry is snapped to integer device pixels; an item centered
    inside a full-screen overlay is not, so we snap it ourselves.

    gridPeriod(dpr) is the smallest logical step whose multiples land exactly on
    integer device pixels (and are themselves integers, as the region API needs):
    1 for integer ratios, 2 for x.5, 4 for x.25 / x.75. Snapping the panel size
    and position to that grid makes both pipelines round to the same device pixel.

    Pure and dependency-free so it is unit-testable in isolation.
*/
.pragma library

// Smallest logical period q (1..16) with q * dpr an integer, i.e. multiples of q
// map onto integer device pixels. Returns 1 for integer/unknown ratios and for
// exotic ratios with no small period (snapping degrades to plain rounding).
function gridPeriod(dpr) {
    if (!(dpr > 0)) {
        return 1
    }
    for (var q = 1; q <= 16; ++q) {
        var device = q * dpr
        if (Math.abs(device - Math.round(device)) < 1e-3) {
            return q
        }
    }
    return 1
}

// Round a logical coordinate or length onto the device-pixel grid (nearest
// multiple of gridPeriod). The result is an integer, so it is also valid for the
// integer-only KWindowEffects region API.
function snap(value, dpr) {
    var q = gridPeriod(dpr)
    return Math.round(value / q) * q
}
