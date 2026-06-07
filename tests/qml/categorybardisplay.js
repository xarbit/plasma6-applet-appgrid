/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Category-bar display policy (#176). The two anchor tabs (Favorites and All)
    are always icon-only — their glyphs are fixed tab markers. The display mode
    decides the dynamic category tabs: "Default" and "Text" show their label,
    "Icon+Text" shows both, "Icon" shows only the icon. Pure functions so the
    rules are testable without standing up the bar.
*/

.pragma library

// Anchor tabs (Favorites, All) are always icon-only; the modes below govern
// the dynamic category tabs.
const MODE_DEFAULT = 0    // categories: text
const MODE_TEXT = 1       // legacy: identical to Default now, dropped from the UI
const MODE_ICON_TEXT = 2  // categories: icon + text
const MODE_ICON = 3       // categories: icon only

// Whether a tab shows its text label. Anchor tabs (Favorites, All) are always
// icon-only. For the dynamic category tabs every mode but icon-only shows text;
// an unrecognised mode (e.g. an undefined config value during startup) falls
// through to showing text so the bar never goes blank.
function showsText(mode, isAnchor) {
    if (isAnchor)
        return false
    return mode !== MODE_ICON
}

// Whether a tab shows its icon. Anchor tabs always do; the category tabs show
// one in Icon+Text and Icon-only.
function showsIcon(mode, isAnchor) {
    if (isAnchor)
        return true
    return mode === MODE_ICON_TEXT || mode === MODE_ICON
}
