/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure mirror-id collection for FavoritesManager, factored out so it can be
    exercised against a plain stub object instead of the real favourites model
    (which only loads in a live Plasma session).

    Import as:
        import "favoritesmigration.js" as FavoritesMigration
*/

.pragma library
.import "favoriteid.js" as FavoriteId

// Collect the storage-id list to mirror into AppFilterModel's
// favorites view. Reads each row's prefixed favoriteId, strips the
// "applications:" scheme, and skips rows with no value.
//
//   model          - object with .count and .data(index, role)
//   favoriteIdRole - int role
//
// Returns [string].
function collectMirrorIds(model, favoriteIdRole) {
    const ids = []
    for (let i = 0; i < model.count; ++i) {
        const raw = model.data(model.index(i, 0), favoriteIdRole)
        if (!raw) continue
        ids.push(FavoriteId.stripPrefix(raw))
    }
    return ids
}
