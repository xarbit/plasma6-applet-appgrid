/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure buffer/apply logic for the standalone settings window (ConfigWindow.qml).
    The window edits a SEPARATE AppGridConfig instance (the buffer) and commits to
    the live one on Apply — standard KCM semantics. This module holds the value
    math so it is unit-tested without instantiating the Kirigami window
    (tst_ConfigBuffer.qml); ConfigWindow.qml is a thin caller.

    Every function operates on bracket-accessible objects (a live/buffer
    AppGridConfig exposes each setting as `obj[key]`), so the tests pass plain
    JS stand-ins. `keys` is the list of editable setting names; `emptyDefaults`
    maps the keys whose KConfigXT default is empty/derived (no public
    defaultXValue Q_PROPERTY) to their main.xml value.
*/
.pragma library

function _eq(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
function _clone(v) { return JSON.parse(JSON.stringify(v)) }

// Deep (value) copy of each key off `src`, detaching the list-valued ones
// (hiddenApps, headerActions) so the snapshot doesn't alias the source object.
function snapshot(src, keys) {
    var snap = ({})
    for (var i = 0; i < keys.length; ++i)
        snap[keys[i]] = _clone(src[keys[i]])
    return snap
}

// Copy live -> buffer for every key (the pages start from what is saved).
// Returns the baseline snapshot of live for a later applyChanged().
function syncFromLive(buffer, live, keys) {
    for (var i = 0; i < keys.length; ++i)
        buffer[keys[i]] = live[keys[i]]
    return snapshot(live, keys)
}

// True when the buffer differs from the live config in any key. JSON compare
// handles the list-valued keys that === compares by reference.
function isDirty(buffer, live, keys) {
    for (var i = 0; i < keys.length; ++i)
        if (!_eq(buffer[keys[i]], live[keys[i]]))
            return true
    return false
}

// Per-key default: the emptyDefaults override if present, else the generated
// defaultXValue Q_PROPERTY on the buffer (a CONSTANT mirror of main.xml).
function defaultFor(buffer, k, emptyDefaults) {
    if (emptyDefaults.hasOwnProperty(k))
        return emptyDefaults[k]
    return buffer["default" + k.charAt(0).toUpperCase() + k.slice(1) + "Value"]
}

// True when the buffer already holds every key's default (Defaults disables).
function atDefaults(buffer, keys, emptyDefaults) {
    for (var i = 0; i < keys.length; ++i)
        if (!_eq(buffer[keys[i]], defaultFor(buffer, keys[i], emptyDefaults)))
            return false
    return true
}

// Stage each key's default into the buffer (Defaults). Not applied/persisted
// until Apply, matching System Settings.
function loadDefaults(buffer, keys, emptyDefaults) {
    for (var i = 0; i < keys.length; ++i)
        buffer[keys[i]] = defaultFor(buffer, keys[i], emptyDefaults)
}

// Write back to live ONLY the keys the user changed against `baseline` (the
// live snapshot taken at the last sync). A key the user left untouched is not
// re-written, so a concurrent launcher live-write (e.g. right-click "Hide
// Application" mutating hiddenApps while the window is open) is preserved
// instead of clobbered by the stale buffer value (#4). Returns the applied keys.
function applyChanged(buffer, live, baseline, keys) {
    var applied = []
    for (var i = 0; i < keys.length; ++i) {
        var k = keys[i]
        if (!_eq(buffer[k], baseline[k])) {
            live[k] = buffer[k]
            applied.push(k)
        }
    }
    return applied
}
