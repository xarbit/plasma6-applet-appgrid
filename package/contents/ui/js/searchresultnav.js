/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Pure navigation helpers for search results while SearchBar owns focus.
*/

.pragma library

function nextIndex(currentIndex, count, step, wrap) {
    if (count <= 0)
        return -1
    if (count === 1)
        return 0

    const idx = Math.max(0, Math.min(count - 1, currentIndex))

    if (step < 0) {
        if (idx <= 0)
            return wrap ? count - 1 : 0
        return idx - 1
    }

    if (step > 0) {
        if (idx <= 0)
            return 1
        if (idx >= count - 1)
            return wrap ? 0 : count - 1
        return idx + 1
    }

    return idx
}
