/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for launchcounts.js — the "storageId=count" <-> map
    encoding that crosses the KConfig boundary every time a launch
    bumps a counter. The format is part of the persisted config, so
    these tests pin both shapes for future-proofing.
*/

import QtQuick
import QtTest
import "launchcounts.js" as LaunchCounts

TestCase {
    name: "LaunchCounts"

    // --- toMap: StringList -> { storageId: count } ---

    function test_toMapParsesValidEntries() {
        const map = LaunchCounts.toMap(["a.desktop=3", "b.desktop=7"])
        compare(map["a.desktop"], 3)
        compare(map["b.desktop"], 7)
    }

    function test_toMapReturnsEmptyForNullOrUndefined() {
        compare(Object.keys(LaunchCounts.toMap(null)).length, 0)
        compare(Object.keys(LaunchCounts.toMap(undefined)).length, 0)
    }

    function test_toMapReturnsEmptyForEmptyList() {
        compare(Object.keys(LaunchCounts.toMap([])).length, 0)
    }

    function test_toMapSkipsMalformedEntries() {
        // No `=`, multiple `=`, missing value — all dropped, valid ones kept.
        const map = LaunchCounts.toMap([
            "noequals",
            "a=1=2",
            "ok.desktop=4"
        ])
        compare(map["ok.desktop"], 4)
        compare(map.noequals, undefined)
        compare(map["a"], undefined)
    }

    function test_toMapCoercesNonIntegerCountToZero() {
        // parseInt("abc") -> NaN -> falls back to 0 via `|| 0`.
        const map = LaunchCounts.toMap(["x.desktop=abc"])
        compare(map["x.desktop"], 0)
    }

    // --- toList: { storageId: count } -> StringList ---

    function test_toListEmitsKeyEqualsValue() {
        const list = LaunchCounts.toList({ "a.desktop": 5 })
        compare(list.length, 1)
        compare(list[0], "a.desktop=5")
    }

    function test_toListSkipsZeroOrNegativeCounts() {
        const list = LaunchCounts.toList({
            "kept.desktop": 1,
            "zero.desktop": 0,
            "negative.desktop": -3
        })
        compare(list.length, 1)
        compare(list[0], "kept.desktop=1")
    }

    function test_toListEmptyForEmptyMap() {
        compare(LaunchCounts.toList({}).length, 0)
    }

    // --- round-trip: config <-> model survives without drift ---

    function test_roundTripPreservesEntries() {
        const original = { "kate.desktop": 12, "konsole.desktop": 3 }
        const list = LaunchCounts.toList(original)
        const back = LaunchCounts.toMap(list)
        compare(back["kate.desktop"], 12)
        compare(back["konsole.desktop"], 3)
    }
}
