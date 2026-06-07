/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for categorybardisplay.js — the per-mode text/icon visibility
    rules for the category bar (#176). The Default mode's split (Favorites
    icon, everything else text) is the easy thing to get wrong, so each mode
    is pinned for both the favorites tab and an ordinary tab.
*/

import QtQuick
import QtTest
import "categorybardisplay.js" as Display

TestCase {
    name: "CategoryBarDisplay"

    // --- Default: category tab text-only ---

    function test_defaultTabShowsTextNoIcon() {
        verify(Display.showsText(Display.MODE_DEFAULT, false))
        verify(!Display.showsIcon(Display.MODE_DEFAULT, false))
    }

    // --- Anchor tabs (Favorites, All) are icon-only in every mode ---

    function test_anchorsAlwaysIconOnly() {
        var modes = [Display.MODE_DEFAULT, Display.MODE_TEXT,
                     Display.MODE_ICON_TEXT, Display.MODE_ICON]
        for (var i = 0; i < modes.length; i++) {
            verify(Display.showsIcon(modes[i], true), "anchor icon, mode " + modes[i])
            verify(!Display.showsText(modes[i], true), "anchor no text, mode " + modes[i])
        }
    }

    // --- Text only: non-fav tabs text, no icon ---

    function test_textModeTabText() {
        verify(Display.showsText(Display.MODE_TEXT, false))
        verify(!Display.showsIcon(Display.MODE_TEXT, false))
    }

    // --- Icon + text: non-fav tabs both ---

    function test_iconTextModeBoth() {
        verify(Display.showsText(Display.MODE_ICON_TEXT, false))
        verify(Display.showsIcon(Display.MODE_ICON_TEXT, false))
    }

    // --- Icon only: non-fav tabs icon, no text ---

    function test_iconModeIconOnly() {
        verify(Display.showsIcon(Display.MODE_ICON, false))
        verify(!Display.showsText(Display.MODE_ICON, false))
    }

    // --- Unrecognised mode (e.g. undefined config) falls back to Default so
    //     the bar can never render a blank tab ---

    function test_undefinedModeFallsBackToDefault() {
        verify(Display.showsText(undefined, false), "undefined tab must still show text")
        verify(!Display.showsIcon(undefined, false))
        verify(Display.showsIcon(undefined, true), "undefined anchor still shows its icon")
        verify(!Display.showsText(undefined, true))
    }

    function test_outOfRangeModeFallsBackToDefault() {
        verify(Display.showsText(99, false))
        verify(!Display.showsIcon(99, false))
    }
}
