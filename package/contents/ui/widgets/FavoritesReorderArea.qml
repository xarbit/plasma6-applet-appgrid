/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Drop handler for the favorites grid. Sits behind the delegates (z
    below them so clicks still reach icons) and handles three drag flavours:

      * Reorder (own drag, source is already a favorite): re-order live as
        the cursor moves, pushing each move onto pendingMoves so we can roll
        back if the user exits without dropping.
      * Add-from-other-tab (own drag, source is *not* yet a favorite): the
        user dragged an icon out of All / a category / recents and dropped
        while the favorites tab is active. Add it as a favorite at the
        cursor position. We never auto-switch tabs during a drag — the user
        must hover the favorites tab button to switch intentionally first
        (see drag-hover handling in CategoryBar).
      * External (file drag from Dolphin / elsewhere): a .desktop becomes an
        app favourite; any other file (an image, a document) becomes a
        file favourite, opened with its default app.
*/

import QtQuick

import "../controllers"
import "../js/favoriteid.js" as FavoriteId

DropArea {
    id: reorderArea

    // The owning GridView. We read its dragSource, sharedFavoritesModel,
    // favoritesActive flag, findFavoriteRow() helper, plus the standard
    // GridView geometry/animation properties.
    required property GridView gridView

    // EdgeAutoScroller instance scrolling the same grid; we defer reorder
    // ticks while it's running so the displaced delegates aren't disturbed.
    required property EdgeAutoScroller edgeScroller

    anchors.fill: parent
    z: -1
    // Always alive when the model is available so external file drags can
    // ferry us to the favorites tab. Internal reorder is gated further down
    // on favoritesActive + non-alphabetical mode.
    enabled: gridView.sharedFavoritesModel !== null

    property var pendingMoves: []
    // True when the live preview of an Add-from-other-tab is currently in
    // the favorites model. We insert the source at the cursor position so
    // the user sees a real ghost slot to drop into; on exit/cancel we pull
    // it back out, on drop we leave it.
    property bool addPreviewActive: false

    readonly property DragSource _source: gridView.dragSource

    // The grid is bound to the grouped (folders) model. Its order is the folder
    // layout, not KAStats order, so reorder goes through moveTopLevel on drop
    // rather than the live KAStats moveRow path below (issue #18).
    readonly property bool _grouped: gridView.favoritesGroupedModel
                                     && gridView.model === gridView.favoritesGroupedModel

    // Drag-create (issue #18): while a single app favourite hovers the inner area
    // of another cell, a "fold" arms — dropping then creates a folder (onto an
    // app) or adds to it (onto a folder); the thin outer edges reorder instead.
    // Only an app source folds; a folder source reorders only.
    property int _foldCandidate: -1
    // Spring-loaded fold: the cursor must dwell this long over a target's icon
    // before the fold arms, so a quick pass-over keeps reordering and only a
    // deliberate pause merges (Dolphin/Kickoff spring-loaded folders).
    readonly property int foldDwellMs: 500
    // Both single and multi drags can fold onto an icon; a folder source can't,
    // and folding is off while drilled inside a folder (folders are single level,
    // no nesting — #18).
    readonly property bool _canFold: _grouped && _sourceId.length > 0
                                     && _source.sourceFolderId.length === 0
                                     && !gridView.favoritesGroupedModel.canGoBack

    // Classify the cursor @p pos (contentItem coords) over target cell @p targetIdx,
    // given the dragged source cell @p sourceIdx (#200):
    //   0 none   — approaching the target's icon, do nothing (keeps the icon
    //              reachable; without this, entering the cell edge swaps first and
    //              the icon slides away before you reach it)
    //   1 fold   — over the icon (or anywhere on a folder cell) → merge
    //   2 reorder — moved past the icon along the travel direction → swap live
    function _dragZone(pos, targetIdx, sourceIdx) {
        const t = gridView.itemAtIndex(targetIdx)
        if (!t)
            return 0
        const fr = t.foldRect
        const fx = t.x + fr.x
        const fy = t.y + fr.y
        if (pos.x >= fx && pos.x <= fx + fr.width && pos.y >= fy && pos.y <= fy + fr.height)
            return 1
        if (sourceIdx < 0)
            return 0
        // Direction of travel, source → target, taken from the grid indices, not
        // the source delegate's pixel centre: itemAtIndex(sourceIdx) can be null
        // right after open (or once the source recycles mid-drag), and the old
        // horizontal fallback then misread a vertical approach as a reorder —
        // swapping instead of folding on the first drag (#200).
        const cols = gridView.effectiveColumns || 1
        let dx = (targetIdx % cols) - (sourceIdx % cols)
        let dy = Math.floor(targetIdx / cols) - Math.floor(sourceIdx / cols)
        const len = Math.hypot(dx, dy) || 1
        dx /= len
        dy /= len
        // Cursor offset from the icon centre projected onto the travel direction:
        // past it (the far side) reorders, before it stays neutral.
        const proj = (pos.x - (fx + fr.width / 2)) * dx + (pos.y - (fy + fr.height / 2)) * dy
        return proj > 0 ? 2 : 0
    }

    // Arm the fold highlight for the candidate row (or clear it when @p index < 0).
    function _armFold(index) {
        const gm = gridView.favoritesGroupedModel
        if (!_source || index < 0 || !gm) {
            if (_source) {
                _source.foldTargetStorageId = ""
                _source.foldTargetFolderId = ""
            }
            return
        }
        // 1 === AbstractGroupedModel.Folder
        if (gm.entryTypeAt(index) === 1) {
            _source.foldTargetFolderId = gm.folderIdAt(index)
            _source.foldTargetStorageId = ""
        } else {
            _source.foldTargetStorageId = FavoriteId.stripPrefix(gm.favoriteIdAt(index))
            _source.foldTargetFolderId = ""
        }
    }

    function _clearFold() {
        foldDwellTimer.stop()
        _foldCandidate = -1
        _armFold(-1)
    }

    // Arms the fold once the cursor has dwelled foldDwellMs over _foldCandidate.
    Timer {
        id: foldDwellTimer
        interval: reorderArea.foldDwellMs
        onTriggered: reorderArea._armFold(reorderArea._foldCandidate)
    }

    // The bare storage id of the active drag's source, cached on DragSource
    // so it survives delegate recycling when the tab switches mid-drag.
    readonly property string _sourceId: _source ? _source.sourceStorageId : ""

    // True when the active own-drag's source is NOT already a favorite —
    // i.e. the user dragged from All / a category / recents and we should
    // treat the drop as "add to favorites" rather than "reorder".
    function _isAddFromOtherTab(drag) {
        if (!_source || !_source.isOwnDrag(drag) || !_sourceId)
            return false
        return gridView.findFavoriteRow(_sourceId) < 0
    }

    // Multi-drag (selection of 2+ favorites) is treated as drag-OUT only.
    // Internal reorder of N items has ambiguous semantics (non-contiguous
    // selection, where do the gaps land?) and most file managers behave the
    // same way: multi-select drag-within stays put, drag-out moves all.
    readonly property bool _isMultiDrag: _source && _source.sourceStorageIds
                                         && _source.sourceStorageIds.length > 1

    // Favourite each dropped external URL: a .desktop becomes an app favourite
    // (by storage id), any other local file an image/document favourite (by URL,
    // opened with its default app). @p insertAt >= 0 places them from that row,
    // -1 appends. Returns the count added.
    function _addExternalUrls(drag, insertAt) {
        if (!drag.hasUrls || !gridView.favoritesActive)
            return 0
        let added = 0
        for (const url of drag.urls) {
            const s = url.toString()
            let id = ""
            if (s.endsWith(".desktop")) {
                const slash = s.lastIndexOf("/")
                id = FavoriteId.toPrefixed(slash >= 0 ? s.substring(slash + 1) : s)
            } else if (s.startsWith("file://")) {
                id = s
            } else {
                continue
            }
            if (insertAt >= 0) {
                gridView.sharedFavoritesModel.addFavorite(id, insertAt)
                insertAt++
            } else {
                gridView.sharedFavoritesModel.addFavorite(id)
            }
            added++
        }
        return added
    }

    // The grid cell index under the drag cursor (drag coords → content coords →
    // GridView cell). Used wherever a drop position is needed; the grouped path
    // keeps its own mapToItem because it also needs the point for _dragZone.
    function _dragPosToIndex(drag) {
        const p = mapToItem(gridView.contentItem, drag.x, drag.y)
        return gridView.indexAt(p.x, p.y)
    }

    onEntered: drag => {
        pendingMoves = []
        addPreviewActive = false
        // No tab auto-switch: an unsolicited tab flip during a drag is
        // jarring. The user reaches the favorites tab by hovering its tab
        // button (CategoryBar handles drag-hover switch).
    }

    onExited: {
        // Undo every pending reorder when the cursor leaves without dropping,
        // on whichever model is driving the order.
        const reorderModel = _grouped ? gridView.favoritesGroupedModel : gridView.sharedFavoritesModel
        while (pendingMoves.length > 0) {
            const [from, to] = pendingMoves.pop()
            if (reorderModel) reorderModel.moveRow(to, from)
        }
        // Pull the live "add preview" back out if it was inserted (the optimistic
        // grouped row + the real KAStats favourite).
        if (addPreviewActive && _sourceId) {
            if (_grouped && gridView.favoritesGroupedModel)
                gridView.favoritesGroupedModel.removeLooseFavorite(_sourceId)
            if (gridView.sharedFavoritesModel)
                gridView.sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(_sourceId))
        }
        addPreviewActive = false
        _clearFold()
    }

    onPositionChanged: drag => {
        if (!_source || !_source.isOwnDrag(drag) || !gridView.sharedFavoritesModel)
            return
        // Grouped grid: hovering a target's icon arms a fold (single or multi);
        // anywhere else swaps live (single drag). A non-favourite
        // (add-from-other-tab) is added on drop instead.
        if (_grouped) {
            const gpos = mapToItem(gridView.contentItem, drag.x, drag.y)
            const gtarget = gridView.indexAt(gpos.x, gpos.y)
            // Add-from-other-tab: favourite it live so it joins as a loose
            // top-level row at the cursor slot, then reflow it exactly like a
            // spring-out — the same live, animated positioning as the non-grouped
            // grid, instead of only adding on drop.
            if (_isAddFromOtherTab(drag) && !addPreviewActive && _sourceId
                    && gridView.favoritesActive) {
                // Optimistic: show the loose row instantly at the cursor
                // (synchronous), then favourite it in KAStats in parallel — so it
                // appears under the pointer, not at the bottom, and without waiting
                // for the KAStats round-trip.
                gridView.favoritesGroupedModel.addLooseFavorite(_sourceId, gtarget)
                gridView.sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(_sourceId))
                addPreviewActive = true
            }
            // Resolve the source row in THIS grid by sid whenever the dragged
            // delegate isn't ours: a spring-out recycled it (sourceItem null), and
            // an add-from-other-tab's sourceItem still points at the origin grid
            // (its gridRow is that grid's index, not the favourites one).
            const gsource = (addPreviewActive || !_source.sourceItem)
                ? gridView.favoritesGroupedModel.indexOfApp(FavoriteId.toPrefixed(_sourceId))
                : _source.sourceItem.gridRow
            const act = addPreviewActive ? Qt.CopyAction : Qt.MoveAction
            if (gsource < 0) {
                // The just-added favourite hasn't reconciled into the grouped
                // model yet — wait for the next event to position it.
                drag.accept(act)
                return
            }
            if (gtarget < 0 || gtarget === gsource) {
                _clearFold()
                drag.accept(act)
                return
            }
            const zone = _canFold ? _dragZone(gpos, gtarget, gsource) : 2
            if (zone === 1) {
                // Over the target's icon → start the dwell; the fold arms only if
                // the cursor lingers (foldDwellTimer), so a quick pass-over still
                // reorders. No reflow while dwelling.
                if (_foldCandidate !== gtarget) {
                    _foldCandidate = gtarget
                    _armFold(-1)
                    foldDwellTimer.restart()
                }
                drag.accept(act)
                return
            }
            _clearFold()
            // A multi-drag only folds (onto an icon); it never reorders — the
            // gaps for an N-item move are ambiguous.
            if (_isMultiDrag) {
                drag.accept(act)
                return
            }
            if (zone === 2) {
                // Past the icon → reflow (swap) live. Don't gate on the move
                // transitions: moveRow jumps straight to gtarget however far the
                // cursor travelled, and the displaced transition animates the
                // catch-up, so a fast drag keeps up instead of skipping swaps.
                // Only a real scroll (flick / edge auto-scroll) holds it off.
                if (gridView.flicking || gridView.moving || edgeScroller.active) {
                    drag.accept(act)
                    return
                }
                gridView.favoritesGroupedModel.moveRow(gsource, gtarget)
                // While adding, don't log the move for rollback — onExited pulls the
                // whole preview out instead.
                if (!addPreviewActive)
                    pendingMoves.push([gsource, gtarget])
            }
            // zone 0 (approaching the icon) → neutral, keep the icon reachable.
            drag.accept(act)
            return
        }
        // Non-grouped grid: multi-drag stays put (drag-out only).
        if (_isMultiDrag) return
        // Reorder fires live even while the move/displaced transitions animate:
        // findFavoriteRow re-reads the source's live row each event and moveRow
        // jumps straight to the cursor's target, so a fast drag keeps up instead
        // of skipping swaps. Only a real scroll (flick / edge auto-scroll) waits.
        if (gridView.flicking || gridView.moving || edgeScroller.active) {
            drag.accept(addPreviewActive || _isAddFromOtherTab(drag)
                        ? Qt.CopyAction : Qt.MoveAction)
            return
        }

        const target = _dragPosToIndex(drag)

        // --- Add-from-other-tab: live ghost slot at the cursor position ---
        // Only when the favorites tab is actually showing; on other tabs
        // we leave the model alone and drop simply does nothing.
        if (_isAddFromOtherTab(drag) && gridView.favoritesActive) {
            const prefixed = FavoriteId.toPrefixed(_sourceId)
            if (!addPreviewActive) {
                const insertAt = target >= 0 ? target : gridView.sharedFavoritesModel.count
                gridView.sharedFavoritesModel.addFavorite(prefixed, insertAt)
                addPreviewActive = true
            } else if (target >= 0) {
                const liveRow = gridView.findFavoriteRow(_sourceId)
                if (liveRow >= 0 && target !== liveRow)
                    gridView.sharedFavoritesModel.moveRow(liveRow, target)
            }
            drag.accept(Qt.CopyAction)
            return
        }

        // --- Reorder existing favorite (or move the just-inserted preview) ---
        const liveSourceRow = _sourceId ? gridView.findFavoriteRow(_sourceId) : -1
        if (liveSourceRow < 0) return
        if (_source.sourceItem) _source.sourceItem.gridRow = liveSourceRow

        // Keep the Copy cursor through the rest of the drag when we're still
        // adding (preview already in the model) so the indicator doesn't flip
        // from + to move-arrow once the preview makes us look like a reorder.
        const action = addPreviewActive ? Qt.CopyAction : Qt.MoveAction

        if (target < 0 || target === liveSourceRow) {
            drag.accept(action)
            return
        }

        gridView.sharedFavoritesModel.moveRow(liveSourceRow, target)
        if (!addPreviewActive)
            pendingMoves.push([liveSourceRow, target])
        if (_source.sourceItem) _source.sourceItem.gridRow = target
        drag.accept(action)
    }

    // Grouped grid drop. A reorder already happened live via moveRow, so just
    // commit it; a new favourite (other tab / external) reconciles in as a loose
    // app at the end.
    function _handleGroupedDrop(drag) {
        const gm = gridView.favoritesGroupedModel
        if (!gm)
            return
        // Armed fold → add the dragged favourite(s) to the target folder, or make
        // a new folder from the target app + the dragged one(s). Single or multi.
        if (_canFold && (_source.foldTargetFolderId.length > 0 || _source.foldTargetStorageId.length > 0)) {
            const dragged = _isMultiDrag ? _source.sourceStorageIds : [_sourceId]
            if (_source.foldTargetFolderId.length > 0) {
                for (var i = 0; i < dragged.length; ++i)
                    gm.addToFolder(_source.foldTargetFolderId, dragged[i])
            } else {
                gm.createFolderFromMembers([_source.foldTargetStorageId].concat(dragged),
                                           i18nd("dev.xarbit.appgrid", "New Folder"))
            }
            // A live-added favourite folded into a folder is now committed there.
            addPreviewActive = false
            _clearFold()
            drag.accept(Qt.MoveAction)
            return
        }
        // Add-from-other-tab that was live-inserted + positioned: it's already
        // favourited at the cursor slot, so just commit (keep it, don't roll back).
        if (addPreviewActive) {
            pendingMoves = []
            addPreviewActive = false
            _clearFold()
            drag.accept(Qt.CopyAction)
            return
        }
        // Otherwise the reorder already happened live via the zone-2 reflow; just
        // commit (clear the rollback log so a stray onExited doesn't undo it).
        if (_source && _source.isOwnDrag(drag) && !_isMultiDrag && !_isAddFromOtherTab(drag)) {
            pendingMoves = []
            _clearFold()
            drag.accept(Qt.MoveAction)
            return
        }
        // Fallback: an add-from-other-tab dropped without a live preview (e.g. not
        // dragged over the grid first) — add it at the end.
        if (_source && _source.isOwnDrag(drag) && gridView.favoritesActive) {
            const sids = _isMultiDrag ? _source.sourceStorageIds : [_sourceId]
            for (var i = 0; i < sids.length; ++i) {
                if (sids[i])
                    gridView.sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(sids[i]))
            }
            drag.accept(Qt.CopyAction)
            return
        }
        if (_addExternalUrls(drag, -1) > 0)
            drag.accept(Qt.CopyAction)
    }

    onDropped: drag => {
        // Stop the dwell now so it can't fire after the drop and arm a stale fold;
        // any fold already armed stays set for the drop handlers below.
        foldDwellTimer.stop()
        if (!gridView.sharedFavoritesModel) return
        if (_grouped) {
            _handleGroupedDrop(drag)
            return
        }

        // Add-from-other-tab: the live preview is already in the model at
        // the cursor position. Just commit by clearing the preview flag so
        // onExited won't roll it back. Falls through (returns) early.
        if (addPreviewActive) {
            addPreviewActive = false
            drag.accept(Qt.CopyAction)
            return
        }

        // Multi-drag own-drag → add any sids not already in favorites at the
        // cursor position. No live preview: a non-contiguous N-item insert
        // doesn't have a sensible ghost form, so we commit on drop instead.
        // Sids that are already favorites are skipped (idempotent), which
        // covers the multi-drag-within-favorites no-op case too.
        if (_isMultiDrag && _source && _source.isOwnDrag(drag)
                && gridView.favoritesActive) {
            let insertAt = _dragPosToIndex(drag)
            if (insertAt < 0) insertAt = gridView.sharedFavoritesModel.count
            const sids = _source.sourceStorageIds
            for (var i = 0; i < sids.length; ++i) {
                const prefixed = FavoriteId.toPrefixed(sids[i])
                if (!gridView.sharedFavoritesModel.isFavorite(prefixed)) {
                    gridView.sharedFavoritesModel.addFavorite(prefixed, insertAt)
                    insertAt++
                }
            }
            drag.accept(Qt.CopyAction)
            return
        }

        // Own drag of an existing favorite → reorder already happened live
        // via onPositionChanged; clear the rollback log so a stray onExited
        // doesn't undo it.
        if (_source && _source.isOwnDrag(drag)) {
            pendingMoves = []
            return
        }

        // External file drag (from Dolphin etc.) — add as favourite, but only
        // when the favorites tab is active; a file silently appearing in
        // Favorites from another tab is confusing.
        if (_addExternalUrls(drag, _dragPosToIndex(drag)) > 0)
            drag.accept(Qt.CopyAction)
    }
}
