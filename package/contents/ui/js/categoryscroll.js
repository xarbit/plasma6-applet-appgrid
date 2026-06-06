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
function pageRightTarget(items, contentX, viewportWidth, contentWidth, spacing) {
    const tentativeRight = contentX + 2 * viewportWidth
    var lastFit = -1
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it) continue
        if (it.x + it.width <= tentativeRight + 1) lastFit = i
        else break
    }
    if (lastFit < 0 || lastFit === items.length - 1)
        return contentWidth

    var fitItem = items[lastFit]
    const target = (fitItem.x + fitItem.width) - viewportWidth + spacing
    var lastItem = items[items.length - 1]
    if (lastItem && lastItem.x < target + viewportWidth + 1)
        return contentWidth
    return target
}

// Target contentX for a leftward page. Retreat one viewport, anchoring the
// first item that becomes fully visible; if that reaches the first item, return
// 0 so the caller clamps to the start and the left arrow collapses.
function pageLeftTarget(items, contentX, viewportWidth, spacing) {
    const tentativeLeft = contentX - viewportWidth
    var firstFit = -1
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it) continue
        if (it.x >= tentativeLeft - 1) { firstFit = i; break }
    }
    if (firstFit <= 0)
        return 0

    const target = items[firstFit].x - spacing
    var firstItem = items[0]
    if (firstItem && firstItem.x + firstItem.width > target - 1)
        return 0
    return target
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
