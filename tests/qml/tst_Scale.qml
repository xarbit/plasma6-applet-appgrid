/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for scale.js — the Size-preset scale policy. Pins the per-preset
    curve (so a tweak is a deliberate table edit) and the #167 two-scale rule:
    text size holds at 1.0 when pinned independently, while the icon scale
    still follows the preset.
*/

import QtQuick
import QtTest
import "scale.js" as Scale

TestCase {
    name: "Scale"

    // --- iconScale: the curve, always following the preset ---

    function test_iconScalePerPreset() {
        compare(Scale.iconScale(0), 0.80)   // Small
        compare(Scale.iconScale(1), 0.90)   // Medium
        compare(Scale.iconScale(2), 1.00)   // Large
    }

    function test_iconScaleClampsBelowRange() {
        compare(Scale.iconScale(-1), 0.80)
    }

    function test_iconScaleClampsAboveRange() {
        compare(Scale.iconScale(5), 1.00)
    }

    // A non-integer preset rounds to the nearest row before lookup.
    function test_iconScaleRoundsNonInteger() {
        compare(Scale.iconScale(0.6), 0.90)   // rounds to 1 (Medium)
        compare(Scale.iconScale(1.4), 0.90)   // rounds to 1 (Medium)
    }

    // --- textScale: curve unless pinned independently (#167) ---

    function test_textScaleFollowsPresetWhenNotIndependent() {
        compare(Scale.textScale(0, false), 0.80)
        compare(Scale.textScale(1, false), 0.90)
        compare(Scale.textScale(2, false), 1.00)
    }

    function test_textScalePinnedToOneWhenIndependent() {
        compare(Scale.textScale(0, true), 1.00)
        compare(Scale.textScale(1, true), 1.00)
        compare(Scale.textScale(2, true), 1.00)
    }

    // Pinning text size must not move the icon scale — they are separate axes.
    function test_independentTextDoesNotAffectIconScale() {
        compare(Scale.iconScale(0), 0.80)
        compare(Scale.iconScale(1), 0.90)
    }
}
