/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Favourite add/remove/toggle for the views, over the controller's
    KActivities favourites model. The controller keeps the filter model and
    the folder layout in step with that model; this file only routes the
    user's actions.
*/

import QtQuick

import "../js/favoriteid.js" as FavoriteId

Item {
    id: manager

    // --- Inputs ---

    // AppGridFavoritesModel from the controller; null disables favourites
    // (e.g. tests without the C++ plugin).
    property var sharedFavoritesModel: null

    // The C++ grouped model (issue #18), for pulling an unfavourited app out
    // of its folder; left null disables folders (e.g. tests).
    property var favoritesGroupedModel: null

    // --- Outputs (panel re-exposes these via aliases) ---

    // The shared model's favourite-id role; -1 while there is no model, so
    // consumers must guard on that before reading row data at the role.
    readonly property int favoriteIdRole: sharedFavoritesModel ? sharedFavoritesModel.favoriteIdRole : -1

    // No layout; pure controller.
    visible: false

    // --- Mutations ---
    //
    // Single source of truth for favourite add/remove/toggle, so views don't
    // each reimplement the prefixing and the folder-cleanup-on-unfavourite
    // dance. All take a bare storageId; prefixing is internal.

    function isFavorite(sid) {
        return !!sharedFavoritesModel && !!sid
            && sharedFavoritesModel.isFavorite(FavoriteId.toPrefixed(sid))
    }

    function addFavorite(sid) {
        if (sharedFavoritesModel && sid)
            sharedFavoritesModel.addFavorite(FavoriteId.toPrefixed(sid))
    }

    // Unfavourite @p sid and pull it out of any folder it was in — folders hold
    // favourites, so a stale member left behind would resurface (#18). The
    // model hides the favourite at once and the controller pushes the shorter
    // list to the folder layout in the same call, so the folder edit below
    // never re-places it as a loose favourite.
    function removeFavorite(sid) {
        if (!sharedFavoritesModel || !sid) return
        sharedFavoritesModel.removeFavorite(FavoriteId.toPrefixed(sid))
        removeFromAnyFolder(sid)
    }

    // Folder removal without unfavouriting — the "Remove from Folder" action and
    // the unfavourite path above both route here (#18).
    function removeFromAnyFolder(sid) {
        if (!favoritesGroupedModel || !sid) return
        const fid = favoritesGroupedModel.folderOfMember(sid)
        if (fid && fid.length > 0)
            favoritesGroupedModel.removeFromFolder(fid, sid)
    }

    function toggleFavorite(sid) {
        if (isFavorite(sid)) {
            removeFavorite(sid)
        } else {
            addFavorite(sid)
        }
    }

    // Favourite @p sid only if it isn't already — adding any app to a folder
    // auto-favourites it in one step (#18).
    function ensureFavorite(sid) {
        if (!isFavorite(sid))
            addFavorite(sid)
    }
}
