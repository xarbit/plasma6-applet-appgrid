/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for favoritetoggle.js — the batch decision behind the Ctrl+D
    favourite shortcut (#193): add-all-if-any-missing, else remove-all, with
    empty sids dropped.
*/

import QtQuick
import QtTest
import "favoritetoggle.js" as FavoriteToggle

TestCase {
    name: "FavoriteToggle"

    function test_singleMissingAdds() {
        const p = FavoriteToggle.plan([{ sid: "a", isFavorite: false }])
        compare(p.add, ["a"])
        compare(p.remove, [])
    }

    function test_singleFavouriteRemoves() {
        const p = FavoriteToggle.plan([{ sid: "a", isFavorite: true }])
        compare(p.add, [])
        compare(p.remove, ["a"])
    }

    function test_anyMissingAddsOnlyTheMissing() {
        // Mixed selection → add the ones not yet favourited, remove nothing.
        const p = FavoriteToggle.plan([
            { sid: "a", isFavorite: true },
            { sid: "b", isFavorite: false },
            { sid: "c", isFavorite: false },
        ])
        compare(p.add, ["b", "c"])
        compare(p.remove, [])
    }

    function test_allFavouritesRemovesAll() {
        const p = FavoriteToggle.plan([
            { sid: "a", isFavorite: true },
            { sid: "b", isFavorite: true },
        ])
        compare(p.add, [])
        compare(p.remove, ["a", "b"])
    }

    function test_emptySidsDropped() {
        // Folder rows resolve to "" — they must never reach add/remove.
        const p = FavoriteToggle.plan([
            { sid: "", isFavorite: false },
            { sid: "a", isFavorite: false },
        ])
        compare(p.add, ["a"])
        compare(p.remove, [])
    }

    function test_emptyInputNoop() {
        const p = FavoriteToggle.plan([])
        compare(p.add, [])
        compare(p.remove, [])
        const p2 = FavoriteToggle.plan([{ sid: "", isFavorite: true }])
        compare(p2.add, [])
        compare(p2.remove, [])
    }
}
