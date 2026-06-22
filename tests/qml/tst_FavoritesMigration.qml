/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for favoritesmigration.js — the migration-decision and
    mirror-id collection logic. Pins the contract that the inline
    versions in GridPanel used to carry; #144 traces back to a bug
    in this exact code path, so the regression coverage matters.
*/

import QtQuick
import QtTest
import "favoritesmigration.js" as FavoritesMigration

TestCase {
    name: "FavoritesMigration"

    // Build a stub that mimics the QAbstractItemModel slice that the
    // production code reads from KAStatsFavoritesModel: count plus
    // index(row, col).data(role)-style access. Each row is a plain
    // object keyed by role.
    function makeModel(rows) {
        return {
            count: rows.length,
            index: function(row, col) { return { row: row, col: col } },
            data: function(idx, role) {
                const row = rows[idx.row]
                return (row && row[role] !== undefined) ? row[role] : null
            }
        }
    }

    readonly property int favRole: 259

    // --- collectMirrorIds ---

    function test_mirrorIdsEmptyModelReturnsEmpty() {
        compare(FavoritesMigration.collectMirrorIds(makeModel([]), favRole), [])
    }

    function test_mirrorIdsStripPrefix() {
        const model = makeModel([
            { 259: "applications:firefox.desktop" },
            { 259: "applications:kate.desktop" },
        ])
        compare(FavoritesMigration.collectMirrorIds(model, favRole),
                ["firefox.desktop", "kate.desktop"])
    }

    function test_mirrorIdsLeaveBareIdsAlone() {
        // stripPrefix is a no-op when the id doesn't start with the scheme.
        const model = makeModel([
            { 259: "firefox.desktop" },
            { 259: "applications:kate.desktop" },
        ])
        compare(FavoritesMigration.collectMirrorIds(model, favRole),
                ["firefox.desktop", "kate.desktop"])
    }

    function test_mirrorIdsSkipFalsyRows() {
        // Same guard as the migration path: empty / null id rows are
        // dropped, not represented as "" entries in the mirror.
        const model = makeModel([
            { 259: "applications:a.desktop" },
            { 259: null },
            { 259: "" },
            { 259: "applications:b.desktop" },
        ])
        compare(FavoritesMigration.collectMirrorIds(model, favRole),
                ["a.desktop", "b.desktop"])
    }
}
