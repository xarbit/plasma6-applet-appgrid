/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure batch-toggle decision for the Ctrl+D favourite shortcut (#193).
*/

.pragma library

// Decide a browser-style favourite toggle for a batch. `entries` is a list of
// { sid, isFavorite }. If any entry isn't a favourite, favourite the missing
// ones; otherwise (all already favourites) remove them all. Empty sids are
// dropped. Returns { add: [sid…], remove: [sid…] } — exactly one is non-empty.
function plan(entries) {
    const valid = (entries || []).filter(e => e && e.sid && e.sid.length > 0)
    if (valid.length === 0)
        return { add: [], remove: [] }
    const missing = valid.filter(e => !e.isFavorite)
    if (missing.length > 0)
        return { add: missing.map(e => e.sid), remove: [] }
    return { add: [], remove: valid.map(e => e.sid) }
}
