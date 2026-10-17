/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Drop handler for the favorites grid. Sits behind the delegates (z
    below them so clicks still reach icons) and handles three drag flavours:

      * Reorder (own drag, source is already a favorite, grouped grid): re-order
        live as the cursor moves, pushing each move onto pendingMoves so we can
        roll back if the user exits without dropping. Alphabetically sorted
        favourites have no order to change.
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
import dev.xarbit.appgrid.models

import "../controllers"
import "../js/favoriteid.js" as FavoriteId

DropArea {
    id: reorderArea

    // The owning GridView. We read its dragSource, sharedFavoritesModel,
    // favoritesActive flag, findFavoriteRow() helper, plus the standard
    // GridView geometry/animation properties.
    required property GridView grid

    // EdgeAutoScroller instance scrolling the same grid; we defer reorder
    // ticks while it's running so the displaced delegates aren't disturbed.
    required property EdgeAutoScroller edgeScroller

    anchors.fill: parent
    z: -1
    // Always alive when the model is available so external file drags can
    // ferry us to the favorites tab. Internal reorder is gated further down
    // on favoritesActive + non-alphabetical mode.
    enabled: grid.sharedFavoritesModel !== null

    property var pendingMoves: []
    // True when the live preview of an Add-from-other-tab is currently in
    // the favorites model. We insert the source at the cursor position so
    // the user sees a real ghost slot to drop into; on exit/cancel we pull
    // it back out, on drop we leave it.
    property bool addPreviewActive: false

    readonly property DragSource _source: grid.dragSource

    // The grid is bound to the grouped (folders) model. Its order is the folder
    // layout, not KAStats order, so reorder goes through moveTopLevel on drop
    // rather than the live KAStats moveRow path below (issue #18).
    readonly property bool _grouped: grid.favoritesGroupedModel
                                     && grid.model === grid.favoritesGroupedModel

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
                                     && !grid.favoritesGroupedModel.canGoBack

    // Classify the cursor @p pos (contentItem coords) over target cell @p targetIdx,
    // given the dragged source cell @p sourceIdx (#200):
    //   0 none   — approaching the target's icon, do nothing (keeps the icon
    //              reachable; without this, entering the cell edge swaps first and
    //              the icon slides away before you reach it)
    //   1 fold   — over the icon (or anywhere on a folder cell) → merge
    //   2 reorder — moved past the icon along the travel direction → swap live
    function _dragZone(pos, targetIdx, sourceIdx) {
        const t = grid.itemAtIndex(targetIdx)
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
        const cols = grid.effectiveColumns || 1
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
        const gm = grid.favoritesGroupedModel
        if (!_source || index < 0 || !gm) {
            if (_source) {
                _source.foldTargetStorageId = ""
                _source.foldTargetFolderId = ""
            }
            return
        }
        // 1 === AbstractGroupedModel.Folder
        if (gm.entryTypeAt(index) === AbstractGroupedModel.Folder) {
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
        return grid.findFavoriteRow(_sourceId) < 0
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
        if (!drag.hasUrls || !grid.favoritesActive)
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
                grid.sharedFavoritesModel.addFavorite(id, insertAt)
                insertAt++
            } else {
                grid.sharedFavoritesModel.addFavorite(id)
            }
            added++
        }
        return added
    }

    // The grid cell index under the drag cursor (drag coords → content coords →
    // GridView cell). Used wherever a drop position is needed; the grouped path
    // keeps its own mapToItem because it also needs the point for _dragZone.
    function _dragPosToIndex(drag) {
        const p = mapToItem(grid.contentItem, drag.x, drag.y)
        return grid.indexAt(p.x, p.y)
    }

    onEntered: drag => {
        pendingMoves = []
        addPreviewActive = false
        // No tab auto-switch: an unsolicited tab flip during a drag is
        // jarring. The user reaches the favorites tab by hovering its tab
        // button (CategoryBar handles drag-hover switch).
    }

    onExited: {
        // Undo every pending reorder (grouped grid only) when the cursor leaves
        // without dropping.
        while (pendingMoves.length > 0) {
            const [from, to] = pendingMoves.pop()
            if (grid.favoritesGroupedModel) grid.favoritesGroupedModel.moveRow(to, from)
        }
        // Pull the live "add preview" back out if it was inserted (the optimistic
        // grouped row + the real KAStats favourite).
        if (addPreviewActive && _sourceId) {
            if (_grouped && grid.favoritesGroupedModel)
                grid.favoritesGroupedModel.removeLooseFavorite(_sourceId)
            if (grid.sharedFavoritesModel)
                grid.sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(_sourceId))
        }
        addPreviewActive = false
        _clearFold()
    }

    onPositionChanged: drag => {
        if (!_source || !_source.isOwnDrag(drag) || !grid.sharedFavoritesModel)
            return
        // Grouped grid: hovering a target's icon arms a fold (single or multi);
        // anywhere else swaps live (single drag). A non-favourite
        // (add-from-other-tab) is added on drop instead.
        if (_grouped) {
            const gpos = mapToItem(grid.contentItem, drag.x, drag.y)
            const gtarget = grid.indexAt(gpos.x, gpos.y)
            // Add-from-other-tab: favourite it live so it joins as a loose
            // top-level row at the cursor slot, then reflow it exactly like a
            // spring-out — the same live, animated positioning as the non-grouped
            // grid, instead of only adding on drop.
            if (_isAddFromOtherTab(drag) && !addPreviewActive && _sourceId
                    && grid.favoritesActive) {
                // Optimistic: show the loose row instantly at the cursor
                // (synchronous), then favourite it in KAStats in parallel — so it
                // appears under the pointer, not at the bottom, and without waiting
                // for the KAStats round-trip.
                grid.favoritesGroupedModel.addLooseFavorite(_sourceId, gtarget)
                grid.sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(_sourceId))
                addPreviewActive = true
            }
            // Resolve the source row in THIS grid by sid whenever the dragged
            // delegate isn't ours: a spring-out recycled it (sourceItem null), and
            // an add-from-other-tab's sourceItem still points at the origin grid
            // (its gridRow is that grid's index, not the favourites one).
            const gsource = (addPreviewActive || !_source.sourceItem)
                ? grid.favoritesGroupedModel.indexOfApp(FavoriteId.toPrefixed(_sourceId))
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
                if (grid.flicking || grid.moving || edgeScroller.active) {
                    drag.accept(act)
                    return
                }
                grid.favoritesGroupedModel.moveRow(gsource, gtarget)
                // While adding, don't log the move for rollback — onExited pulls the
                // whole preview out instead.
                if (!addPreviewActive)
                    pendingMoves.push([gsource, gtarget])
            }
            // zone 0 (approaching the icon) → neutral, keep the icon reachable.
            drag.accept(act)
            return
        }
        // Flat grid: favourites sorted alphabetically (the grouped grid holds
        // the stored order otherwise). The sort places a favourite, so there is
        // nothing to reorder; a single app dragged in from another view is
        // favourited at once (and taken back out if the drag leaves).
        if (!_isMultiDrag && _isAddFromOtherTab(drag) && grid.favoritesActive) {
            if (!addPreviewActive) {
                grid.sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(_sourceId))
                addPreviewActive = true
            }
            drag.accept(Qt.CopyAction)
        }
    }

    // Grouped grid drop. A reorder already happened live via moveRow, so just
    // commit it; a new favourite (other tab / external) reconciles in as a loose
    // app at the end.
    function _handleGroupedDrop(drag) {
        const gm = grid.favoritesGroupedModel
        if (!gm)
            return
        // Armed fold → add the dragged favourite(s) to the target folder, or make
        // a new folder from the target app + the dragged one(s). Single or multi.
        if (_canFold && (_source.foldTargetFolderId.length > 0 || _source.foldTargetStorageId.length > 0)) {
            const dragged = _isMultiDrag ? _source.sourceStorageIds : [_sourceId]
            if (_source.foldTargetFolderId.length > 0) {
                for (let i = 0; i < dragged.length; ++i)
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
        if (_source && _source.isOwnDrag(drag) && grid.favoritesActive) {
            const sids = _isMultiDrag ? _source.sourceStorageIds : [_sourceId]
            for (let i = 0; i < sids.length; ++i) {
                if (sids[i])
                    grid.sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(sids[i]))
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
        if (!grid.sharedFavoritesModel) return
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

        // Multi-drag own-drag → favourite any sids that aren't yet (the sort
        // places them). Sids that are already favorites are skipped
        // (idempotent), which covers a drag within the favourites too.
        if (_isMultiDrag && _source && _source.isOwnDrag(drag)
                && grid.favoritesActive) {
            const sids = _source.sourceStorageIds
            for (let i = 0; i < sids.length; ++i) {
                const prefixed = FavoriteId.toPrefixed(sids[i])
                if (!grid.sharedFavoritesModel.isFavorite(prefixed))
                    grid.sharedFavoritesModel.addFavorite(prefixed)
            }
            drag.accept(Qt.CopyAction)
            return
        }

        // Any other own drag: nothing to reorder in a sorted grid.
        if (_source && _source.isOwnDrag(drag))
            return

        // External file drag (from Dolphin etc.) — add as favourite, but only
        // when the favorites tab is active; a file silently appearing in
        // Favorites from another tab is confusing.
        if (_addExternalUrls(drag, _dragPosToIndex(drag)) > 0)
            drag.accept(Qt.CopyAction)
    }
}
