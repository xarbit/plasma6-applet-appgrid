/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure category-bar scroll geometry — clamp, max-offset, reserve/viewport,
    page-target, ensure-visible. Extracted from CategoryBar.qml so the
    Flickable-free math is unit-testable.

    All widths are in pixels. Item lists are arrays of { x, width } (or null for
    a not-yet-realised delegate, which is skipped) in left-to-right order.
*/

.pragma library

// Maximum scrollable offset: how far contentX can travel before the right edge
// of the content reaches the right edge of the viewport.
function maxContentX(contentWidth, viewportWidth) {
    return Math.max(0, contentWidth - viewportWidth)
}

// Cap a raw wheel delta so one fast / high-resolution notch can't leap across
// many categories. angleDelta arrives as pixels and hi-res wheels report large
// values; the cap is 60% of the viewport (a partial page) with a pixel floor so
// a narrow bar still moves a sensible amount. Sign is preserved.
function clampWheelDelta(raw, viewportWidth, minCap) {
    const cap = Math.max(viewportWidth * 0.6, minCap)
    return Math.max(-cap, Math.min(cap, raw))
}

// Clamp a desired contentX into [0, maxX].
function clampContentX(target, contentWidth, viewportWidth) {
    return Math.max(0, Math.min(maxContentX(contentWidth, viewportWidth), target))
}

// Clamp a scroll/paging target to the furthest valid offset for the reserves it
// will LAND in, not the ones in effect now. reserveGeometry gives the viewport at
// the target (e.g. the right arrow collapsed once the last tab is flush, widening
// it); clamping against that stops an animated move from overshooting when a
// reserve collapses mid-glide and the contentX animation drives past the new bound
// faster than it can be re-clamped (#172). containerWidth is the strip's full
// width; contentWidth is the natural (unscrolled) content width.
function clampToReserve(target, containerWidth, contentWidth, arrowWidth) {
    const viewport = reserveGeometry(target, containerWidth, contentWidth, arrowWidth).viewport
    return clampContentX(target, contentWidth, viewport)
}

// Effective viewport width for rightward scrolls. At the left edge
// (contentX <= 0) the left-arrow slot is collapsed but expands right after the
// scroll, narrowing the viewport by arrowWidth; targets computed against the
// raw width would leave the landed item half-clipped once the arrow appears.
function viewportAfterRightScroll(flickWidth, contentX, arrowWidth) {
    return flickWidth - (contentX <= 0 ? arrowWidth : 0)
}

// Viewport geometry for the category strip at a scroll offset. Each scroll arrow
// reserves its width by insetting the strip: leftReserve once scrolled off the
// start; the right arrow shows (reserving on the right) until the last tab is
// flush — judged against the viewport WITHOUT the right reserve (container minus
// the left reserve) and the natural content width, so it never depends on the
// width it controls. Both edges use the one rule "is there content past this
// side". Returns { leftReserve, rightShown, viewport }; viewport is the container
// minus both reserves. Computed together so a binding reading the viewport never
// lands on a half-updated reserve — a transient full-width frame that, on a jump,
// strands the strip short of the edge (#172). 1px slack avoids sub-pixel flicker.
function reserveGeometry(contentX, containerWidth, naturalContentWidth, arrowWidth) {
    const leftReserve = contentX > 0 ? arrowWidth : 0
    const rightShown = contentX + (containerWidth - leftReserve) < naturalContentWidth - 1
    return {
        leftReserve: leftReserve,
        rightShown: rightShown,
        viewport: containerWidth - leftReserve - (rightShown ? arrowWidth : 0),
    }
}

// Page the category strip one viewport in `dir` (+1 = right, -1 = left). One
// rule for both directions: advance ~a viewport and align to a tab boundary so
// the leading edge always shows a whole tab — paging right lands the last
// (rightmost) tab fully visible, left the first. Independent of tab width, bar
// width and display mode, because it works only from the live tab rects. `items`
// is the tab geometry ({x, width}; nulls for unrealised delegates are skipped).
// Returns the target contentX, clamped to [0, contentWidth - viewportWidth].
function pageTarget(items, contentX, viewportWidth, contentWidth, dir) {
    const maxX = Math.max(0, contentWidth - viewportWidth)
    if (dir > 0) {
        const viewRight = contentX + viewportWidth
        const reach = viewRight + viewportWidth          // one viewport ahead
        var edge = -1
        for (var i = 0; i < items.length; i++) {
            var ri = items[i]
            if (!ri) continue
            var r = ri.x + ri.width
            if (r <= viewRight + 1) continue             // already fully visible
            if (edge < 0) edge = r                       // first new tab (covers a tab wider than a page)
            if (r <= reach + 1) edge = r                 // furthest whole tab a viewport ahead
            else break
        }
        if (edge < 0) return maxX                        // nothing more to the right → end
        // edge is a tab's right edge; put it flush with the viewport's right so
        // that tab shows fully. Always make progress, never overscroll.
        return Math.min(maxX, Math.max(contentX + 1, edge - viewportWidth))
    }
    const reach = contentX - viewportWidth               // one viewport back
    var left = -1
    for (var j = items.length - 1; j >= 0; j--) {
        var lj = items[j]
        if (!lj) continue
        if (lj.x >= contentX - 1) continue               // not before the current left edge
        if (left < 0) left = lj.x                        // first new tab (covers a tab wider than a page)
        if (lj.x >= reach - 1) left = lj.x               // furthest whole tab a viewport back
        else break
    }
    if (left < 0) return 0                               // nothing more to the left → start
    // left is a tab's left edge; align it to the viewport's left so that tab
    // shows fully. Always make progress.
    return Math.max(0, Math.min(contentX - 1, left))
}

// Target contentX to bring a selected item fully into view, or null if it is
// already visible. Scroll left to reveal its left edge, or right to reveal its
// right edge (against the post-scroll viewport, so the arrow expansion doesn't
// re-clip it).
function ensureVisibleTarget(itemX, itemWidth, contentX, flickWidth, viewportAfterRight, spacing) {
    const viewLeft = contentX
    const viewRight = contentX + flickWidth
    const itemRight = itemX + itemWidth
    if (itemX < viewLeft)
        return itemX - spacing
    if (itemRight > viewRight)
        return itemRight - viewportAfterRight + spacing
    return null
}

// Minimum width for a row of `count` icon-only tabs, each at `tabWidth` (its
// icon plus breathing-room padding) with `spacing` between them — below this
// the tabs would squish, so the row should overflow into a scroll instead (#176).
function iconRowMinWidth(count, tabWidth, spacing) {
    return count > 0 ? count * tabWidth + (count - 1) * spacing : 0
}
