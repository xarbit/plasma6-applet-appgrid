/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure helpers for the customizable header-action layout. The config stores
    one ordered StringList of "id:placement" tokens (placement = bar | menu |
    off); list order is display order. parse() turns that into ordered bar/menu
    id lists for rendering; migrateFromLegacy() folds the old
    powerButtonOrder/powerButtonsHidden config into the new format.

    No QML/Plasma deps so the logic is unit-testable in isolation.
*/
.pragma library

// Catalogue of arrangeable header actions, in default order + placement.
// Used to validate ids, seed ids missing from saved config (forward-compat
// when a later version adds an action), and drive the config UI.
var CATALOGUE = [
    { id: "updateCheck", placement: "bar", icon: "system-software-update" },
    { id: "sleep", placement: "bar", icon: "system-suspend" },
    { id: "restart", placement: "bar", icon: "system-reboot" },
    { id: "shutdown", placement: "bar", icon: "system-shutdown" },
    { id: "lock", placement: "menu", icon: "system-lock-screen" },
    { id: "logout", placement: "menu", icon: "system-log-out" },
    { id: "switchuser", placement: "menu", icon: "system-switch-user" },
];

// Freedesktop icon name for an action id, or empty for an unknown id. Single
// source for both the live header strip and the config editor.
function iconFor(id) {
    for (var i = 0; i < CATALOGUE.length; ++i) {
        if (CATALOGUE[i].id === id)
            return CATALOGUE[i].icon || "";
    }
    return "";
}

function _defaultPlacement(id) {
    for (var i = 0; i < CATALOGUE.length; ++i) {
        if (CATALOGUE[i].id === id)
            return CATALOGUE[i].placement;
    }
    return null; // unknown id
}

// Parse the headerActions StringList into ordered { bar: [ids], menu: [ids] }.
// Order follows the config list. Unknown ids are dropped, "off" is skipped
// (disabled), and any known id absent from the list is appended at its default
// placement so an action added in a later release still surfaces.
// universalBuild (default true) gates update-only actions: updateCheck only
// exists when the in-app update checker is compiled in (universal tarball).
function _excluded(id, universalBuild) {
    var uni = (universalBuild === undefined) ? true : universalBuild;
    return id === "updateCheck" && !uni;
}

// Walk the config StringList in order, invoking callback(id, placement) for
// each token that is a known, not-yet-seen, not-excluded action. Returns the
// `seen` set so callers can append the catalogue actions that were absent.
// Shared by parse() and entries(), which only differ in how they consume each
// (id, placement) pair.
function _walkConfig(configList, universalBuild, callback) {
    var seen = {};
    var list = configList || [];
    for (var i = 0; i < list.length; ++i) {
        var token = String(list[i]);
        var sep = token.indexOf(":");
        var id = sep >= 0 ? token.substring(0, sep) : token;
        var placement = sep >= 0 ? token.substring(sep + 1) : _defaultPlacement(id);
        if (_defaultPlacement(id) === null || seen[id] || _excluded(id, universalBuild))
            continue;
        seen[id] = true;
        callback(id, placement);
    }
    return seen;
}

function parse(configList, universalBuild) {
    var bar = [];
    var menu = [];
    var seen = _walkConfig(configList, universalBuild, function (id, placement) {
        if (placement === "bar")
            bar.push(id);
        else if (placement === "menu")
            menu.push(id);
        // "off" or anything else → disabled, skipped
    });
    for (var j = 0; j < CATALOGUE.length; ++j) {
        var c = CATALOGUE[j];
        if (seen[c.id] || _excluded(c.id, universalBuild))
            continue;
        if (c.placement === "bar")
            bar.push(c.id);
        else if (c.placement === "menu")
            menu.push(c.id);
    }
    return { bar: bar, menu: menu };
}

// Full ordered entry list for the config editor: every catalogue action with
// its placement (bar | menu | off). Config order first; ids absent from the
// config are appended at their default placement. Unknown ids dropped.
function entries(configList, universalBuild) {
    var out = [];
    var seen = _walkConfig(configList, universalBuild, function (id, placement) {
        if (placement !== "bar" && placement !== "menu" && placement !== "off")
            placement = _defaultPlacement(id);
        out.push({ id: id, placement: placement });
    });
    for (var j = 0; j < CATALOGUE.length; ++j) {
        if (!seen[CATALOGUE[j].id] && !_excluded(CATALOGUE[j].id, universalBuild))
            out.push({ id: CATALOGUE[j].id, placement: CATALOGUE[j].placement });
    }
    return out;
}

// Serialize editor entries ([{ id, placement }]) back to the config StringList.
function serialize(entryList) {
    var out = [];
    var list = entryList || [];
    for (var i = 0; i < list.length; ++i)
        out.push(list[i].id + ":" + list[i].placement);
    return out;
}

// Build a headerActions list from the legacy powerButtonOrder (top-level slot
// order) + powerButtonsHidden (hidden ids). The legacy "session" slot was a
// dropdown grouping lock/logout/switchuser, so it expands to those three at
// menu placement. updateCheck (new) is placed on the bar.
function migrateFromLegacy(order, hidden) {
    var hiddenSet = {};
    var h = hidden || [];
    for (var i = 0; i < h.length; ++i)
        hiddenSet[h[i]] = true;

    var slots = (order && order.length > 0) ? order : ["sleep", "restart", "shutdown", "session"];
    var result = ["updateCheck:bar"];
    var sessionHidden = hiddenSet["session"];

    for (var j = 0; j < slots.length; ++j) {
        var slot = slots[j];
        if (slot === "session") {
            var sub = ["lock", "logout", "switchuser"];
            for (var k = 0; k < sub.length; ++k) {
                var off = sessionHidden || hiddenSet[sub[k]];
                result.push(sub[k] + ":" + (off ? "off" : "menu"));
            }
        } else if (_defaultPlacement(slot) !== null) {
            result.push(slot + ":" + (hiddenSet[slot] ? "off" : "bar"));
        }
    }
    return result;
}
