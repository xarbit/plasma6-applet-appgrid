/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for customheaderactions.js — parsing, serialization, runnable
    filtering, placement split, and id generation for user-defined header
    actions (#196). The header strip and the settings editor both rely on these
    pure helpers, so the round-trip and the "drop half-typed rows" rule are
    pinned here.
*/

import QtQuick
import QtTest
import "customheaderactions.js" as CHA

TestCase {
    name: "CustomHeaderActions"

    function _json(o) { return JSON.stringify(o) }

    // --- parse: normalization + validation ---

    function test_parseNormalizesFields() {
        var list = [_json({ id: "a", command: "  ls  " })]
        var r = CHA.parse(list)
        compare(r.length, 1)
        compare(r[0].id, "a")
        compare(r[0].command, "ls")                 // trimmed
        compare(r[0].icon, "utilities-terminal-symbolic")    // default icon
        compare(r[0].placement, "menu")             // default placement
        compare(r[0].runInTerminal, false)
    }

    function test_parseKeepsEmptyCommandForEditing() {
        // A half-typed row (no command yet) survives parse so the editor can
        // render it; only the strip's runnable() drops it.
        var r = CHA.parse([_json({ id: "a", label: "x", command: "" })])
        compare(r.length, 1)
        compare(r[0].command, "")
    }

    function test_parseDropsMalformedAndIdless() {
        var r = CHA.parse(["not json", _json({ label: "no id" }), _json({ id: "ok", command: "x" })])
        compare(r.length, 1)
        compare(r[0].id, "ok")
    }

    function test_parseDropsDuplicateIds() {
        var r = CHA.parse([_json({ id: "a", command: "1" }), _json({ id: "a", command: "2" })])
        compare(r.length, 1)
        compare(r[0].command, "1")  // first wins
    }

    function test_parseInvalidPlacementFallsBackToMenu() {
        var r = CHA.parse([_json({ id: "a", command: "x", placement: "bogus" })])
        compare(r[0].placement, "menu")
    }

    // --- serialize: drops empty-command rows, round-trips the rest ---

    function test_serializeDropsEmptyCommand() {
        var entries = [
            { id: "a", label: "L", icon: "i", command: "run", runInTerminal: true, placement: "bar" },
            { id: "b", label: "", icon: "", command: "   ", runInTerminal: false, placement: "menu" }
        ]
        var out = CHA.serialize(entries)
        compare(out.length, 1)
        var back = CHA.parse(out)
        compare(back[0].id, "a")
        compare(back[0].command, "run")
        compare(back[0].runInTerminal, true)
        compare(back[0].placement, "bar")
        compare(back[0].icon, "i")
    }

    function test_serializeParseRoundTrip() {
        var list = [_json({ id: "x", label: "Restart", icon: "system-reboot",
                            command: "systemctl --user restart plasma-plasmashell",
                            runInTerminal: false, placement: "bar" })]
        compare(CHA.serialize(CHA.parse(list)), list)
    }

    // --- runnable: only entries with a command ---

    function test_runnableFiltersEmptyCommand() {
        var entries = CHA.parse([
            _json({ id: "a", command: "go" }),
            _json({ id: "b", command: "" })
        ])
        var r = CHA.runnable(entries)
        compare(r.length, 1)
        compare(r[0].id, "a")
    }

    // --- renderLayout: split runnable into bar/menu, drop off ---

    function test_renderLayoutSplitsByPlacement() {
        var list = [
            _json({ id: "a", command: "1", placement: "bar" }),
            _json({ id: "b", command: "2", placement: "menu" }),
            _json({ id: "c", command: "3", placement: "off" }),
            _json({ id: "d", command: "",  placement: "bar" })   // empty → dropped
        ]
        var lay = CHA.renderLayout(list)
        compare(lay.bar.length, 1)
        compare(lay.bar[0].id, "a")
        compare(lay.menu.length, 1)
        compare(lay.menu[0].id, "b")
    }

    function test_renderLayoutPreservesOrder() {
        var list = [
            _json({ id: "a", command: "1", placement: "bar" }),
            _json({ id: "b", command: "2", placement: "bar" })
        ]
        var lay = CHA.renderLayout(list)
        compare(lay.bar[0].id, "a")
        compare(lay.bar[1].id, "b")
    }

    // --- displayLabel: label, else command fallback ---

    function test_displayLabelFallsBackToCommand() {
        compare(CHA.displayLabel({ label: "", command: "htop" }), "htop")
        compare(CHA.displayLabel({ label: "Top", command: "htop" }), "Top")
    }

    // --- makeId / blank: collision-free, deterministic ---

    function test_makeIdAvoidsCollisions() {
        compare(CHA.makeId([]), "custom-1")
        compare(CHA.makeId(["custom-1", "custom-2"]), "custom-3")
        compare(CHA.makeId(["custom-2"]), "custom-1")  // lowest free
    }

    function test_blankIsBarTerminalDefault() {
        var b = CHA.blank([])
        compare(b.id, "custom-1")
        compare(b.command, "")
        compare(b.icon, "utilities-terminal-symbolic")
        compare(b.placement, "bar")
        compare(b.runInTerminal, false)
    }
}
