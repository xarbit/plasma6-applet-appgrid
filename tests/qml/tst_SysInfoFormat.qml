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

    function test_migratedLayout() {
        const t = SysInfoFormat.clipboardText(fullInfo, true, 12, 5)
        const lines = t.split("\n")
        compare(lines.length, 10)
        compare(lines[0], "AppGrid: 1.10.0")
        compare(lines[1], "Install: AUR")
        compare(lines[4], "Plasma: 6.2.0")
        compare(lines[8], "Screens: 1x 2256x1504")
        compare(lines[9], "Favorites: KAStats (12; backup 5)")
    }

    function test_notMigratedFavoritesLine() {
        const t = SysInfoFormat.clipboardText(fullInfo, false, 0, 7)
        const lines = t.split("\n")
        compare(lines[9], "Favorites: not migrated (7)")
    }

    function test_missingFieldsRenderEmpty() {
        const t = SysInfoFormat.clipboardText({}, false, 0, 0)
        const lines = t.split("\n")
        compare(lines[0], "AppGrid: ")
        compare(lines[7], "OS: ")
        compare(lines[9], "Favorites: not migrated (0)")
    }

    function test_nullInfoDoesNotThrow() {
        const t = SysInfoFormat.clipboardText(null, false, 0, 3)
        compare(t.split("\n")[9], "Favorites: not migrated (3)")
    }
}
