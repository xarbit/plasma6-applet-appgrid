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

    // --- decideMigrationActions ---

    function test_migrationPlanIsEmptyForEmptyInputs() {
        const actions = FavoritesMigration.decideMigrationActions(
            makeModel([]), favRole, [])
        compare(actions.idsToRemove, [])
        compare(actions.prefixedToPort, [])
    }

    function test_migrationRemovesSeededDefaultsBeforePort() {
        // Plasma seeds Kickoff defaults on a fresh KAStats namespace
        // (Konsole/Discover/Settings). Without the remove pass, the
        // user's actual 1.7.x favorites would union with these and
        // re-introduce #144.
        const seeded = makeModel([
            { 259: "applications:org.kde.konsole.desktop" },
            { 259: "applications:org.kde.discover.desktop" },
            { 259: "applications:systemsettings.desktop" },
        ])
        const actions = FavoritesMigration.decideMigrationActions(
            seeded, favRole, ["firefox.desktop", "thunderbird.desktop"])

        compare(actions.idsToRemove, [
            "applications:org.kde.konsole.desktop",
            "applications:org.kde.discover.desktop",
            "applications:systemsettings.desktop",
        ])
        compare(actions.prefixedToPort, [
            "applications:firefox.desktop",
            "applications:thunderbird.desktop",
        ])
    }

    function test_migrationPrefixesBareLegacyIds() {
        const actions = FavoritesMigration.decideMigrationActions(
            makeModel([]), favRole, ["firefox.desktop"])
        compare(actions.prefixedToPort, ["applications:firefox.desktop"])
    }

    function test_migrationLeavesAlreadyPrefixedLegacyIdsAlone() {
        // toPrefixed is idempotent on already-scheme'd ids.
        const actions = FavoritesMigration.decideMigrationActions(
            makeModel([]),
            favRole,
            ["applications:foo.desktop", "bar.desktop"])
        compare(actions.prefixedToPort, [
            "applications:foo.desktop",
            "applications:bar.desktop",
        ])
    }

    function test_migrationSkipsModelRowsWithEmptyId() {
        // KAStats can briefly hold rows whose favoriteId hasn't been
        // populated yet — those must not land in the remove list as
        // empty strings, which would be a no-op or worse.
        const model = makeModel([
            { 259: "applications:a.desktop" },
            { 259: "" },
            { 259: null },
            { 259: "applications:b.desktop" },
        ])
        const actions = FavoritesMigration.decideMigrationActions(
            model, favRole, [])
        compare(actions.idsToRemove, [
            "applications:a.desktop",
            "applications:b.desktop",
        ])
    }

    function test_migrationConvertsNonStringIdsToString() {
        // Defensive: if KAStats hands back a typed value, the remove
        // call needs a string. Pin that the helper coerces.
        const model = makeModel([{ 259: 42 }])
        const actions = FavoritesMigration.decideMigrationActions(
            model, favRole, [])
        compare(actions.idsToRemove, ["42"])
    }

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
