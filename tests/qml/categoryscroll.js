/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure category-bar scroll geometry. The clamp / max-offset / viewport /
    arrow-visibility / page-target / ensure-visible math used to live inline in
    CategoryBar.qml over a live Flickable, where the #172 case (content just
    over the viewport while the expanding left-arrow narrows it) could not be
    asserted. Extracted here as Flickable-free functions so it is testable; the
    in-frame _anchoredRight glue stays in the QML (it is animation-frame state).

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

// Clamp a desired contentX into [0, maxX] and report whether it lands exactly
// on the right edge. anchoredRight lets the caller pin contentX to the moving
// maxX while the left-arrow slot expands afterwards (which shrinks the viewport
// and grows maxX) — without it the right arrow lingers because contentX falls
// short of the new bound (#172).
function clampContentX(target, contentWidth, viewportWidth) {
    const maxX = maxContentX(contentWidth, viewportWidth)
    const contentX = Math.max(0, Math.min(maxX, target))
    return { contentX: contentX, anchoredRight: contentX === maxX && maxX > 0 }
}

// Effective viewport width for rightward scrolls. At the left edge
// (contentX <= 0) the left-arrow slot is collapsed but expands right after the
// scroll, narrowing the viewport by arrowWidth; targets computed against the
// raw width would leave the landed item half-clipped once the arrow appears.
function viewportAfterRightScroll(flickWidth, contentX, arrowWidth) {
    return flickWidth - (contentX <= 0 ? arrowWidth : 0)
}

// Which scroll arrows should show at a given offset. left: scrolled off the
// start. right: content still extends past the viewport (1px slack avoids
// sub-pixel flicker at the exact bound).
function arrowVisibility(contentX, viewportWidth, contentWidth) {
    return {
        left: contentX > 0,
        right: contentX + viewportWidth < contentWidth - 1,
    }
}

// Dead space between the right edge of the content and the right edge of the
// viewport at a given offset. The #172 assertion hook: after a full right
// scroll this must be 0 — no gap past the last category.
function trailingGap(contentX, contentWidth, viewportWidth) {
    return Math.max(0, viewportWidth - (contentWidth - contentX))
}

// Target contentX for a rightward page. Advance ~one viewport, anchoring the
// last fully-fitting item so it isn't half-clipped; if the page would touch the
// last item at all, return contentWidth so the caller clamps to the end and the
// right arrow can collapse on the same click.
// Page forward by ~one viewport. The first tab that isn't fully visible (the
// one straddling the right fold) leads the next page, aligned just inside the
// left edge — so no page is skipped and no tab is cut, whatever the tab width
// (text / icon+text / icon). Snaps to the end only once the last tab would
// itself come fully into view, so the right arrow can collapse on that page.
// Page the category strip one viewport in `dir` (+1 = right, -1 = left). One
// rule for both directions: advance ~a viewport and align to a tab boundary so
// the leading edge always shows a whole tab — paging right lands with the last
// (rightmost) tab fully visible, paging left with the first (leftmost) tab fully
// visible. Independent of tab width, bar width and display mode (text /
// icon+text / icon), because it works only from the live tab rects. `items` is
// the tab geometry ({x, width}; nulls for unrealised delegates are skipped).
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
