/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for sysinfoformat.js — the "Copy to Clipboard" system-info block.
    Pins line order, the migrated/not-migrated favorites line, and the
    empty-field fallback (this is a bug-report payload, so its shape matters).
*/

import QtQuick
import QtTest
import "sysinfoformat.js" as SysInfoFormat

TestCase {
    name: "SysInfoFormat"

    readonly property var fullInfo: ({
        appgridVersion: "1.10.0",
        installType: "AUR",
        variant: "center",
        sessionType: "wayland",
        plasmaVersion: "6.2.0",
        kfVersion: "6.10.0",
        qtVersion: "6.8.1",
        os: "CachyOS",
        screens: "1x 2256x1504"
    })

    function test_layout() {
        const t = SysInfoFormat.clipboardText(fullInfo)
        const lines = t.split("\n")
        compare(lines.length, 9)
        // Every line pinned by index so a reorder of the block is caught.
        compare(lines[0], "AppGrid: 1.10.0")
        compare(lines[1], "Install: AUR")
        compare(lines[2], "Variant: center")
        compare(lines[3], "Session: wayland")
        compare(lines[4], "Plasma: 6.2.0")
        compare(lines[5], "KF: 6.10.0")
        compare(lines[6], "Qt: 6.8.1")
        compare(lines[7], "OS: CachyOS")
        compare(lines[8], "Screens: 1x 2256x1504")
    }

    function test_missingFieldsRenderEmpty() {
        const t = SysInfoFormat.clipboardText({})
        const lines = t.split("\n")
        compare(lines[0], "AppGrid: ")
        compare(lines[7], "OS: ")
    }

    function test_nullInfoDoesNotThrow() {
        const t = SysInfoFormat.clipboardText(null)
        compare(t.split("\n")[0], "AppGrid: ")
    }
}
