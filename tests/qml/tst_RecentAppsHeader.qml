/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for RecentAppsHeader: a recent app that gets uninstalled drops
    out of the row once the app list reloads, instead of keeping its tile.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "RecentAppsHeader"
    when: windowShown

    // The QML-visible surface of AppFilterModel the header reads. installed
    // stands in for the app list and is changed in place, without a change
    // signal, like the C++ model: only modelReset (what the proxy emits when
    // the app list reloads) tells the header.
    QtObject {
        id: appsStub
        property var recentApps: ["kept.desktop", "removed.desktop"]
        property var installed: ({ "kept.desktop": "Kept", "removed.desktop": "Removed" })
        property int iconGeneration: 0
        signal modelReset()
        function getByStorageId(sid) {
            const name = installed[sid]
            return name === undefined ? ({}) : ({ name: name, iconName: "", desktopFile: "" })
        }
        function isNewApp(sid) { return false }
    }

    // The names of the tiles the row shows: a tile is shown while its app
    // resolves (the delegate's visible binding; the header has no window here,
    // so read the condition rather than the effective visibility).
    function shownNames(header) {
        const names = []
        const collect = item => {
            if (item.appData !== undefined && item.modelData !== undefined && item.appData.name !== undefined)
                names.push(item.appData.name)
            for (let i = 0; i < item.children.length; ++i)
                collect(item.children[i])
        }
        collect(header)
        return names.sort()
    }

    function test_uninstalledRecentDropsOutOnReload() {
        const c = Qt.createComponent("../../package/contents/ui/widgets/RecentAppsHeader.qml")
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        const header = c.createObject(testCase, { appsModel: appsStub, hoverAnimation: 0, shadowEnabled: false, width: 400 })
        verify(header, "header created")
        compare(shownNames(header), ["Kept", "Removed"])

        delete appsStub.installed["removed.desktop"]
        appsStub.modelReset()
        compare(shownNames(header), ["Kept"])
        header.destroy()
    }
}
