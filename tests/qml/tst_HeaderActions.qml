/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for headeractions.js — parsing the "id:placement" config into
    ordered bar/menu lists (order, off, unknown ids, forward-compat append)
    and the legacy powerButton -> headerActions migration.
*/

import QtQuick
import QtTest
import "headeractions.js" as HeaderActions

TestCase {
    name: "HeaderActions"

    function test_parseDefaultLayout() {
        var r = HeaderActions.parse(["updateCheck:bar", "sleep:bar", "hibernate:menu", "restart:bar", "shutdown:bar", "lock:menu", "logout:menu", "switchuser:menu"]);
        compare(r.bar.join(","), "updateCheck,sleep,restart,shutdown");
        compare(r.menu.join(","), "hibernate,lock,logout,switchuser,settings");
    }

    function test_parsePreservesOrderAndPlacement() {
        // Explicit entries honour config order + placement; the rest are
        // appended at their default placement.
        var r = HeaderActions.parse(["lock:bar", "sleep:menu"]);
        compare(r.bar[0], "lock");
        compare(r.menu[0], "sleep");
        verify(r.bar.indexOf("restart") >= 0); // appended default (bar)
        verify(r.menu.indexOf("logout") >= 0); // appended default (menu)
    }

    function test_parseOffDisables() {
        var r = HeaderActions.parse(["sleep:off", "restart:bar"]);
        verify(r.bar.indexOf("sleep") < 0);
        verify(r.menu.indexOf("sleep") < 0);
        verify(r.bar.indexOf("restart") >= 0);
    }

    function test_parseDropsUnknownIds() {
        var r = HeaderActions.parse(["bogus:bar", "sleep:bar"]);
        verify(r.bar.indexOf("bogus") < 0);
        verify(r.bar.indexOf("sleep") >= 0);
    }

    function test_parseEmptyUsesCatalogueDefaults() {
        var r = HeaderActions.parse([]);
        compare(r.bar.join(","), "updateCheck,sleep,restart,shutdown");
        compare(r.menu.join(","), "hibernate,lock,logout,switchuser,settings");
    }

    function test_entriesCoversAllInOrder() {
        var e = HeaderActions.entries(["lock:bar", "sleep:off"]);
        // explicit first, in config order, then the rest at defaults
        compare(e[0].id, "lock");
        compare(e[0].placement, "bar");
        compare(e[1].id, "sleep");
        compare(e[1].placement, "off");
        compare(e.length, 9); // whole catalogue present
    }

    function test_entriesEmptyIsCatalogueDefaults() {
        var e = HeaderActions.entries([]);
        compare(e.length, 9);
        compare(e[0].id, "updateCheck");
        compare(e[0].placement, "bar");
    }

    function test_serializeRoundTrip() {
        var list = ["lock:bar", "sleep:off", "updateCheck:menu"];
        var e = HeaderActions.entries(list);
        var s = HeaderActions.serialize(e);
        // re-parsing the serialized form yields the same entries
        compare(HeaderActions.serialize(HeaderActions.entries(s)).join(","), s.join(","));
        compare(s[0], "lock:bar");
        compare(s[1], "sleep:off");
        compare(s[2], "updateCheck:menu");
    }

    function test_parseOmitsUpdateCheckOnNonUniversal() {
        // Distro build (no in-app updater): updateCheck must not surface even
        // if the saved config places it on the bar.
        var r = HeaderActions.parse(["updateCheck:bar", "sleep:bar"], false);
        verify(r.bar.indexOf("updateCheck") < 0);
        verify(r.menu.indexOf("updateCheck") < 0);
        verify(r.bar.indexOf("sleep") >= 0);
    }

    function test_entriesOmitsUpdateCheckOnNonUniversal() {
        var e = HeaderActions.entries([], false);
        compare(e.length, 8); // catalogue minus updateCheck
        for (var i = 0; i < e.length; ++i)
            verify(e[i].id !== "updateCheck");
    }

    function test_iconForKnownAndUnknown() {
        compare(HeaderActions.iconFor("sleep"), "system-suspend");
        compare(HeaderActions.iconFor("shutdown"), "system-shutdown");
        compare(HeaderActions.iconFor("updateCheck"), "system-software-update");
        compare(HeaderActions.iconFor("bogus"), "");
    }

    // --- layout: parse + availability filter ---

    function test_layoutDropsUnavailableActions() {
        // Only sleep + lock are available; the rest of the default layout falls
        // away while order is preserved.
        var avail = { "sleep": true, "lock": true };
        var r = HeaderActions.layout([], true, avail);
        compare(r.bar.join(","), "sleep");
        compare(r.menu.join(","), "lock");
    }

    function test_layoutMissingIdCountsUnavailable() {
        // An id absent from the availability map is treated as unavailable.
        var r = HeaderActions.layout(["sleep:bar"], true, {});
        compare(r.bar.length, 0);
        compare(r.menu.length, 0);
    }

    function test_layoutKeepsConfigOrderAmongAvailable() {
        var avail = { "restart": true, "shutdown": true };
        var r = HeaderActions.layout(["shutdown:bar", "restart:bar"], true, avail);
        compare(r.bar.join(","), "shutdown,restart");
    }

    // --- entriesEqual: ordered deep compare ---

    function test_entriesEqualMatches() {
        var a = [{ id: "sleep", placement: "bar" }, { id: "lock", placement: "menu" }];
        var b = [{ id: "sleep", placement: "bar" }, { id: "lock", placement: "menu" }];
        verify(HeaderActions.entriesEqual(a, b));
    }

    function test_entriesEqualDiffersOnLength() {
        var a = [{ id: "sleep", placement: "bar" }];
        var b = [{ id: "sleep", placement: "bar" }, { id: "lock", placement: "menu" }];
        verify(!HeaderActions.entriesEqual(a, b));
    }

    function test_entriesEqualDiffersOnPlacementOrOrder() {
        var base = [{ id: "sleep", placement: "bar" }, { id: "lock", placement: "menu" }];
        verify(!HeaderActions.entriesEqual(base,
            [{ id: "sleep", placement: "menu" }, { id: "lock", placement: "menu" }]));
        verify(!HeaderActions.entriesEqual(base,
            [{ id: "lock", placement: "menu" }, { id: "sleep", placement: "bar" }]));
    }
}
