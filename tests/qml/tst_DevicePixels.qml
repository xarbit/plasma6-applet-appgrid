/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for devicepixels.js — the logical→device-pixel grid period and the
    snap that keeps the frosted panel's edges aligned with the blur region under
    fractional scaling (#188). The grid period per ratio and the invariant that a
    snapped value lands on an integer device pixel are pinned here.
*/

import QtQuick
import QtTest
import "devicepixels.js" as DevicePixels

TestCase {
    name: "DevicePixels"

    function test_gridPeriodIntegerRatios() {
        compare(DevicePixels.gridPeriod(1), 1)
        compare(DevicePixels.gridPeriod(2), 1)
        compare(DevicePixels.gridPeriod(3), 1)
    }

    function test_gridPeriodHalfRatios() {
        compare(DevicePixels.gridPeriod(1.5), 2)
        compare(DevicePixels.gridPeriod(2.5), 2)
    }

    function test_gridPeriodQuarterRatios() {
        compare(DevicePixels.gridPeriod(1.25), 4)
        compare(DevicePixels.gridPeriod(1.75), 4)
    }

    function test_gridPeriodInvalidFallsBackToOne() {
        compare(DevicePixels.gridPeriod(0), 1)
        compare(DevicePixels.gridPeriod(-1), 1)
        compare(DevicePixels.gridPeriod(undefined), 1)
    }

    // At 1.75 the grid is 4 logical px; snap rounds to the nearest multiple.
    function test_snapAtQuarterScaleUsesFourPxGrid() {
        compare(DevicePixels.snap(100, 1.75), 100)
        compare(DevicePixels.snap(101, 1.75), 100)
        compare(DevicePixels.snap(103, 1.75), 104)
        compare(DevicePixels.snap(99, 1.75), 100)
    }

    function test_snapAtHalfScaleUsesTwoPxGrid() {
        compare(DevicePixels.snap(100, 1.5), 100)
        compare(DevicePixels.snap(101, 1.5), 102)
    }

    function test_snapAtIntegerScaleIsRounding() {
        compare(DevicePixels.snap(305, 1), 305)
        compare(DevicePixels.snap(305.4, 1), 305)
        compare(DevicePixels.snap(305.6, 2), 306)
    }

    // The defining invariant: a snapped logical value maps onto an integer
    // device pixel for every supported ratio, so paint and blur region align.
    function test_snappedValueLandsOnIntegerDevicePixel() {
        const ratios = [1.25, 1.5, 1.75, 2.0, 2.5]
        for (let i = 0; i < ratios.length; ++i) {
            const device = DevicePixels.snap(517, ratios[i]) * ratios[i]
            verify(Math.abs(device - Math.round(device)) < 1e-6)
        }
    }
}
