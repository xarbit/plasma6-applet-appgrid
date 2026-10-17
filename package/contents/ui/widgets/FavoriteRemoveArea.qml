/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Drag-out removal for the favourites grid: dragging a favourite (or a
    multi-selection of them) onto empty space and dropping removes it, and a
    dragged folder is dissolved, its members returning to the favourites.
    While such a drag hovers here, the drag source is flagged so the cell
    shows a ✕. Drops over the Favorites tab never reach here (the tab hover
    blocks them).
*/

import QtQuick


DropArea {
    id: root

    // The shared DragSource of the launcher's own drags.
    property var dragSource: null
    // FavoritesManager: favourites and their folders.
    property var favoritesManager: null

    // The dragged sids that are actually favorites (empty unless this is an
    // own drag with at least one favorite source). Drives both the ✕ marker
    // and the drop removal.
    function _favoriteSids(drag) {
        const src = root.dragSource
        if (!src || src.blockedOnFavoritesTab || !src.isOwnDrag(drag) || !root.favoritesManager) {
            return []
        }
        const all = src.sourceStorageIds.length > 0 ? src.sourceStorageIds : [src.sourceStorageId]
        return all.filter(sid => root.favoritesManager.isFavorite(sid))
    }

    // The dragged folder's id, if a folder cell is being dragged here (#18).
    function _folderId(drag) {
        const src = root.dragSource
        return (src && !src.blockedOnFavoritesTab && src.isOwnDrag(drag)) ? (src.sourceFolderId || "") : ""
    }

    // Both helpers above return empty while blockedOnFavoritesTab is set, so
    // nothing here arms or removes — the drop over the Favorites tab cancels.
    function _removable(drag) {
        return _favoriteSids(drag).length > 0 || _folderId(drag).length > 0
    }

    // Hovering empty space with a favorite/folder drag arms removal: flag the
    // drag source (the cell shows a ✕) and accept so the cursor reads
    // droppable. onExited reverts when the cursor returns to the grid.
    onEntered: drag => {
        if (root._removable(drag)) {
            root.dragSource.dropWillRemove = true
            drag.accept(Qt.MoveAction)
        } else {
            // Not a removable drag (e.g. blocked over the Favorites tab):
            // reject so the platform shows the forbidden indicator instead
            // of a droppable cursor.
            drag.accepted = false
        }
    }
    onPositionChanged: drag => {
        if (root._removable(drag))
            drag.accept(Qt.MoveAction)
        else
            drag.accepted = false
    }
    onExited: { if (root.dragSource) root.dragSource.dropWillRemove = false }

    onDropped: drag => {
        // A folder dropped here is dissolved (members return to favourites),
        // the folder equivalent of removing an icon.
        const folderId = root._folderId(drag)
        const folders = root.favoritesManager ? root.favoritesManager.favoritesGroupedModel : null
        if (folderId.length > 0 && folders) {
            folders.ungroupFolder(folderId)
            drag.accept(Qt.MoveAction)
            return
        }
        const sids = root._favoriteSids(drag)
        if (sids.length === 0) {
            return
        }
        // Through the manager, so a favourite in a folder leaves the folder too.
        for (let i = 0; i < sids.length; ++i) {
            root.favoritesManager.removeFavorite(sids[i])
        }
        drag.accept(Qt.MoveAction)
    }
}
