/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for favoriteid.js — the "applications:" prefix helpers used
    to bridge bare AppGrid storage ids and KAStats' scheme-prefixed
    favorite ids. Drag-reorder depends on stable round-tripping, so we
    pin the current contract for every shape we hand to either side.
*/

import QtQuick
import QtTest
import "../../package/contents/ui/js/favoriteid.js" as FavoriteId

TestCase {
    name: "FavoriteId"

    // --- toPrefixed: adds scheme only when no colon is present ---

    function test_toPrefixedAddsSchemeToBareId() {
        compare(FavoriteId.toPrefixed("kate.desktop"),
                "applications:kate.desktop")
    }

    function test_toPrefixedLeavesAlreadyPrefixedAlone() {
        compare(FavoriteId.toPrefixed("applications:kate.desktop"),
                "applications:kate.desktop")
    }

    function test_toPrefixedLeavesForeignSchemeAlone() {
        // Any id that already contains a colon is treated as a scheme'd
        // form and passed through. Lets the helper survive a future
        // KAStats id shape without mangling it.
        compare(FavoriteId.toPrefixed("file:///tmp"), "file:///tmp")
    }

    function test_toPrefixedReturnsBareSchemeForFalsy() {
        compare(FavoriteId.toPrefixed(""), "applications:")
        compare(FavoriteId.toPrefixed(null), "applications:")
        compare(FavoriteId.toPrefixed(undefined), "applications:")
    }

    // --- stripPrefix: removes scheme when present, no-op otherwise ---

    function test_stripPrefixRemovesScheme() {
        compare(FavoriteId.stripPrefix("applications:kate.desktop"),
                "kate.desktop")
    }

    function test_stripPrefixLeavesBareIdAlone() {
        compare(FavoriteId.stripPrefix("kate.desktop"), "kate.desktop")
    }

    function test_stripPrefixLeavesForeignSchemeAlone() {
        compare(FavoriteId.stripPrefix("file:///tmp"), "file:///tmp")
    }

    function test_stripPrefixReturnsEmptyForNonString() {
        compare(FavoriteId.stripPrefix(null), "")
        compare(FavoriteId.stripPrefix(undefined), "")
        compare(FavoriteId.stripPrefix(123), "")
        compare(FavoriteId.stripPrefix({}), "")
    }

    // --- hasPrefix: case-sensitive exact match ---

    function test_hasPrefixTrueForSchemedId() {
        verify(FavoriteId.hasPrefix("applications:kate.desktop"))
    }

    function test_hasPrefixFalseForBareId() {
        verify(!FavoriteId.hasPrefix("kate.desktop"))
    }

    function test_hasPrefixIsCaseSensitive() {
        verify(!FavoriteId.hasPrefix("APPLICATIONS:kate.desktop"))
    }

    function test_hasPrefixFalseForNonString() {
        verify(!FavoriteId.hasPrefix(null))
        verify(!FavoriteId.hasPrefix(undefined))
        verify(!FavoriteId.hasPrefix(42))
    }

    // --- round-trip: drag-reorder relies on this being stable ---

    function test_roundTripBareId() {
        const id = "kate.desktop"
        compare(FavoriteId.stripPrefix(FavoriteId.toPrefixed(id)), id)
    }

    function test_roundTripAlreadyPrefixed() {
        const id = "applications:kate.desktop"
        compare(FavoriteId.toPrefixed(FavoriteId.stripPrefix(id)), id)
    }
}
