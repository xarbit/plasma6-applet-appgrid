/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Easing curve for EdgeAutoScroller — proximity-driven, quadratic.
    Pulled out as a pure function so the math can be unit-tested
    without standing up a Flickable + DropArea drag fixture.
*/

.pragma library

// Pixels to advance the viewport on the next tick, given:
//   scrollingUp     - true if scrolling upward (drag near top edge)
//   dragY           - drag position inside the viewport, in viewport pixels
//   edge            - thickness of the active edge zone in pixels
//   viewportHeight  - flickable height
//   minPx, maxPx    - scroll-speed bounds (per tick)
//
// Returns a non-negative magnitude; the caller applies sign based on
// scroll direction. The quadratic profile keeps motion gentle just
// inside the zone and ramps up near the edge.
function deltaPerTick(scrollingUp, dragY, edge, viewportHeight, minPx, maxPx) {
    const inside = scrollingUp
        ? (edge - Math.max(0, dragY))
        : (dragY - (viewportHeight - edge))
    const t = Math.max(0, Math.min(1, inside / edge))
    return minPx + (maxPx - minPx) * t * t
}
