/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for themecolors.js — the single tint() seam every tinted
    background goes through. It must carry the theme color's RGB unchanged
    (so dark/light/high-contrast themes stay correct) and apply only the
    requested alpha, discarding the source's own alpha.
*/

import QtQuick
import QtTest
import "themecolors.js" as ThemeColors

TestCase {
    name: "ThemeColors"

    function test_tintPreservesRgbAppliesAlpha() {
        const out = ThemeColors.tint(Qt.rgba(0.2, 0.4, 0.6, 1.0), 0.5)
        fuzzyCompare(out.r, 0.2, 0.001)
        fuzzyCompare(out.g, 0.4, 0.001)
        fuzzyCompare(out.b, 0.6, 0.001)
        fuzzyCompare(out.a, 0.5, 0.001)
    }

    // Source alpha is irrelevant; only the rgb channels are carried over.
    function test_tintDiscardsSourceAlpha() {
        const out = ThemeColors.tint(Qt.rgba(0.1, 0.1, 0.1, 0.3), 0.9)
        fuzzyCompare(out.a, 0.9, 0.001)
    }
}
