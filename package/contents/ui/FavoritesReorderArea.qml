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
      * External (.desktop file drag from Dolphin / elsewhere): same as
        Add-from-other-tab but for arbitrary file URLs.
*/

import QtQuick
import org.kde.plasma.plasmoid

import "controllers"
import "js/favoriteid.js" as FavoriteId

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

    onEntered: drag => {
        pendingMoves = []
        addPreviewActive = false
        // No tab auto-switch: an unsolicited tab flip during a drag is
        // jarring. The user reaches the favorites tab by hovering its tab
        // button (CategoryBar handles drag-hover switch).
    }

    onExited: {
        // Undo every pending reorder when the cursor leaves without dropping.
        while (pendingMoves.length > 0) {
            const [from, to] = pendingMoves.pop()
            gridView.sharedFavoritesModel.moveRow(to, from)
        }
        // Pull the live "add preview" back out if it was inserted.
        if (addPreviewActive && _sourceId && gridView.sharedFavoritesModel) {
            gridView.sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(_sourceId))
        }
        addPreviewActive = false
    }

    onPositionChanged: drag => {
        if (!_source || !_source.isOwnDrag(drag) || !gridView.sharedFavoritesModel)
            return
        // Multi-drag: no internal reorder. Drag-out target receives the
        // multi-URI mime data; falling through here would attempt to reorder
        // only the originating delegate, splitting it from its selection.
        if (_isMultiDrag) return
        // Hold off on reorder while existing animations or auto-scroll are
        // settling. Subsequent positionChanged events will retry.
        if (gridView.move.running || gridView.moveDisplaced.running
                || gridView.flicking || gridView.moving
                || edgeScroller.active) {
            drag.accept(addPreviewActive || _isAddFromOtherTab(drag)
                        ? Qt.CopyAction : Qt.MoveAction)
            return
        }

        const pos = mapToItem(gridView.contentItem, drag.x, drag.y)
        const target = gridView.indexAt(pos.x, pos.y)

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

    onDropped: drag => {
        if (!gridView.sharedFavoritesModel) return

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
            const pos = mapToItem(gridView.contentItem, drag.x, drag.y)
            let insertAt = gridView.indexAt(pos.x, pos.y)
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

        // External drag (e.g. .desktop file from Dolphin) — add as favorite,
        // but only when the favorites tab is active. Dropping a .desktop on
        // the All tab silently appearing in Favorites is confusing.
        if (!drag.hasUrls || !gridView.favoritesActive) return
        const pos = mapToItem(gridView.contentItem, drag.x, drag.y)
        let insertAt = gridView.indexAt(pos.x, pos.y)
        for (const url of drag.urls) {
            let id = url.toString()
            // Only accept .desktop drops. KAStats can ingest other URLs but
            // launching a .desktop is the expected favorites use case.
            if (!id.endsWith(".desktop")) continue
            // Strip file:// or path prefix; KAStats's normaliser accepts
            // bare storage IDs (basename) or the prefixed form.
            const slash = id.lastIndexOf("/")
            if (slash >= 0) id = id.substring(slash + 1)
            const prefixed = FavoriteId.toPrefixed(id)
            if (insertAt >= 0) {
                gridView.sharedFavoritesModel.addFavorite(prefixed, insertAt)
                insertAt++
            } else {
                gridView.sharedFavoritesModel.addFavorite(prefixed)
            }
        }
        drag.accept(Qt.CopyAction)
    }
}
