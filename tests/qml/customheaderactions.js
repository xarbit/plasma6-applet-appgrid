/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure helpers for user-defined custom header actions (#196). Each action runs
    a user command — optionally in the configured terminal — and is configurable
    in the Header Actions settings page (label, icon, command, placement).

    Stored as a StringList in config: one JSON object per entry, with the fields
    { id, label, icon, command, runInTerminal, placement }. These live in their
    own config key (customHeaderActions) and carry their own placement, so the
    built-in headeractions.js model stays untouched; the header strip simply
    appends the custom bar/menu items after the built-in ones.

    No QML/Plasma deps so the logic is unit-testable in isolation.
*/
.pragma library

var DEFAULT_ICON = "utilities-terminal-symbolic";
var PLACEMENTS = ["bar", "menu", "off"];

function _normalizePlacement(p) {
    return PLACEMENTS.indexOf(p) >= 0 ? p : "menu";
}

// Parse the config StringList into normalized entry objects. Each element is a
// JSON object string; malformed elements and ones without a usable id are
// dropped. Fields are normalized (default icon, valid placement, boolean
// runInTerminal, trimmed strings) but empty-command entries are KEPT so the
// editor can render a half-typed row. Use runnable()/renderLayout() for the
// strip, which require a command.
function parse(configList) {
    var out = [];
    var list = configList || [];
    var seen = {};
    for (var i = 0; i < list.length; ++i) {
        var entry = null;
        try {
            entry = JSON.parse(String(list[i]));
        } catch (e) {
            continue;
        }
        if (!entry || typeof entry !== "object")
            continue;
        var id = entry.id ? String(entry.id) : "";
        if (!id || seen[id])
            continue;
        seen[id] = true;
        out.push({
            id: id,
            label: entry.label ? String(entry.label).trim() : "",
            icon: entry.icon ? String(entry.icon).trim() : DEFAULT_ICON,
            command: entry.command ? String(entry.command).trim() : "",
            runInTerminal: entry.runInTerminal === true,
            placement: _normalizePlacement(entry.placement)
        });
    }
    return out;
}

// Serialize editor entries back to the config StringList (one JSON string each).
// Empty-command rows are dropped so a half-finished entry never persists or
// shows in the header; the icon falls back to the terminal default.
function serialize(entries) {
    var out = [];
    var list = entries || [];
    for (var i = 0; i < list.length; ++i) {
        var e = list[i];
        var command = e.command ? String(e.command).trim() : "";
        if (!command)
            continue;
        out.push(JSON.stringify({
            id: e.id ? String(e.id) : makeId(_idsOf(out)),
            label: e.label ? String(e.label).trim() : "",
            icon: e.icon ? String(e.icon).trim() : DEFAULT_ICON,
            command: command,
            runInTerminal: e.runInTerminal === true,
            placement: _normalizePlacement(e.placement)
        }));
    }
    return out;
}

function _idsOf(jsonList) {
    var ids = [];
    for (var i = 0; i < jsonList.length; ++i) {
        try { ids.push(JSON.parse(jsonList[i]).id); } catch (e) { /* skip */ }
    }
    return ids;
}

// Runnable subset for the live header: entries with a non-empty command. The
// strip never shows an action it can't run.
function runnable(entries) {
    var out = [];
    var list = entries || [];
    for (var i = 0; i < list.length; ++i) {
        if (list[i].command && String(list[i].command).trim().length > 0)
            out.push(list[i]);
    }
    return out;
}

// Display label for a custom action: the user label, or the command itself as a
// fallback so an icon-only/unlabelled action still reads in tooltips/menus.
function displayLabel(entry) {
    return entry.label && entry.label.length > 0 ? entry.label : entry.command;
}

// Split runnable entries into ordered { bar, menu } by placement (off dropped),
// preserving config order. The header strip appends these after the built-ins.
function renderLayout(configList) {
    var r = runnable(parse(configList));
    var bar = [];
    var menu = [];
    for (var i = 0; i < r.length; ++i) {
        if (r[i].placement === "bar")
            bar.push(r[i]);
        else if (r[i].placement === "menu")
            menu.push(r[i]);
    }
    return { bar: bar, menu: menu };
}

// Fresh id not colliding with existing ones: "custom-<n>" with the lowest free
// n. Deterministic (no RNG) so the editor and tests are reproducible.
function makeId(existingIds) {
    var used = {};
    var ids = existingIds || [];
    for (var i = 0; i < ids.length; ++i)
        used[String(ids[i])] = true;
    var n = 1;
    while (used["custom-" + n])
        ++n;
    return "custom-" + n;
}

// A blank entry for the editor's "+" button. Defaults to a bar terminal action.
function blank(existingIds) {
    return {
        id: makeId(existingIds),
        label: "",
        icon: DEFAULT_ICON,
        command: "",
        runInTerminal: false,
        placement: "bar"
    };
}
