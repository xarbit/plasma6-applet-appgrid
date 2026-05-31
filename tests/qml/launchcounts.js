/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    launchCounts encoding helpers. The config stores per-app launch
    counts as a StringList of "storageId=count" entries (KConfig only
    supports primitive list types); AppFilterModel consumes a plain
    {storageId: count} map. Conversion lives in one place so layout
    files don't open-code the format.
*/

.pragma library

function toMap(list) {
    var map = {}
    if (!list)
        return map
    for (var i = 0; i < list.length; ++i) {
        var parts = list[i].split("=")
        if (parts.length === 2)
            map[parts[0]] = parseInt(parts[1]) || 0
    }
    return map
}

function toList(map) {
    var list = []
    for (var key in map) {
        if (map[key] > 0)
            list.push(key + "=" + map[key])
    }
    return list
}
