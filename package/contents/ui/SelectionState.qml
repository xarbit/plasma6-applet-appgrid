/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Shared multi-selection state for the grid views (AppGridView and
    CategoryGridView). Each view instantiates one as a child and supplies
    a `sidAt(index)` callback plus a live `gridCount` binding. The state
    object — `sids` (sid → true map) plus `anchor` index — drives the
    Ctrl/Shift+click, Shift+Arrow, and Ctrl+A flows, and is read by
    AppIconDelegate to show the selection halo and ✓ badge.

    Why a map keyed by storageId rather than an Array of indices:
      * Selection survives reorder of the underlying model — KAStats
        favorites can be drag-reordered while items stay selected.
      * O(1) membership for the per-delegate `selected` binding, which
        re-evaluates for every visible item on every selection change.

    Mutation pattern: helpers build a fresh `sids` object and reassign
    `selectionSids` whole, so QML bindings observe the change. In-place
    mutation would not trip the property-changed signal.
*/

import QtQuick

Item {
    id: selection

    // Callable: maps a flat grid index to the app's storageId. Returns ""
    // for invalid indices. Owner must supply — without it the range/select-
    // all operations cannot resolve which apps to mark.
    property var sidAt: function(idx) { return "" }
    // Live total item count for the grid (visible apps). selectAll iterates
    // [0, gridCount); range clamps to it.
    property int gridCount: 0

    // The selection itself: { storageId: true, … }. Reassigned (not mutated)
    // so QML re-evaluates bindings that read it.
    property var selectionSids: ({})
    // Index of the last toggle (Ctrl+click / Space) — pivot for Shift+click
    // and Shift+Arrow range selection. -1 = no anchor.
    property int anchor: -1

    readonly property int selectionCount: {
        var n = 0
        for (var k in selectionSids) if (selectionSids[k]) ++n
        return n
    }

    function contains(sid) {
        return sid && selectionSids[sid] === true
    }

    function sidList() {
        var arr = []
        for (var k in selectionSids) if (selectionSids[k]) arr.push(k)
        return arr
    }

    function toggleAt(idx) {
        const sid = sidAt(idx)
        if (!sid) return
        var copy = Object.assign({}, selectionSids)
        if (copy[sid]) delete copy[sid]
        else copy[sid] = true
        selectionSids = copy
        anchor = idx
    }

    function rangeTo(idx) {
        if (idx < 0 || idx >= gridCount) return
        if (anchor < 0) {
            toggleAt(idx)
            return
        }
        const lo = Math.min(anchor, idx)
        const hi = Math.max(anchor, idx)
        var copy = Object.assign({}, selectionSids)
        for (var i = lo; i <= hi; ++i) {
            const sid = sidAt(i)
            if (sid) copy[sid] = true
        }
        selectionSids = copy
    }

    function selectAll(currentIdx) {
        var copy = {}
        for (var i = 0; i < gridCount; ++i) {
            const sid = sidAt(i)
            if (sid) copy[sid] = true
        }
        selectionSids = copy
        if (anchor < 0) anchor = currentIdx >= 0 ? currentIdx : 0
    }

    function clear() {
        if (selectionCount === 0 && anchor < 0) return
        selectionSids = ({})
        anchor = -1
    }

    // Esc clears any pending selection. Returns true if the key was
    // consumed (selection existed) so the caller can stop event propagation;
    // false lets the event bubble to the window's close handler.
    function consumeEscape() {
        if (selectionCount === 0 && anchor < 0) return false
        clear()
        return true
    }

    // Apply Ctrl / Shift modifier semantics to a left-click. Returns true if
    // the click was consumed (toggle or range select), false for a plain
    // click that should fall through to launch. Centralises the modifier
    // branching that would otherwise duplicate across every view delegate.
    function applyModClick(mouse, idx) {
        if (mouse.modifiers & Qt.ControlModifier) { toggleAt(idx); return true }
        if (mouse.modifiers & Qt.ShiftModifier)   { rangeTo(idx);  return true }
        return false
    }

    // Right-click on an unselected item collapses any pending selection so
    // the context menu operates on the clicked item only. Selected-item
    // right-clicks pass through untouched (the menu's multi-aware branch
    // picks up the live selection).
    function purgeIfOutside(sid) {
        if (selectionCount > 0 && !contains(sid)) clear()
    }

    // Drive an arrow-key navigation step that may double as a Shift-extend
    // of the selection. With Shift held: anchor is fixed (set lazily from
    // the pre-move cursor), the caller's `moveFn` advances the cursor, and
    // the new cursor index extends the range. Without Shift: selection
    // collapses and the cursor moves. Callers stay terse:
    //
    //     selection.extendOrMove(event,
    //         function() { moveCurrentIndexDown() },
    //         function() { return currentIndex })
    function extendOrMove(event, moveFn, currentIdxFn) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0
        if (shift) {
            if (anchor < 0) anchor = currentIdxFn()
            moveFn()
            rangeTo(currentIdxFn())
        } else {
            clear()
            moveFn()
        }
    }

    // Parallel list of file:// URLs for the currently selected apps. The
    // model lookup lives here (rather than at each view) so all callers
    // resolve URLs the same way. `appsModel` must expose
    // `getByStorageId(sid) -> { desktopFile, … }` (AppFilterModel does).
    function desktopFileUrls(appsModel) {
        var urls = []
        if (!appsModel) return urls
        const sids = sidList()
        for (var i = 0; i < sids.length; ++i) {
            const a = appsModel.getByStorageId(sids[i])
            if (a && a.desktopFile) urls.push("file://" + a.desktopFile)
        }
        return urls
    }
}
