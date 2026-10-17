/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Both hidden-apps lists (the h: view and the settings page) load on their
    own model, and show their empty state with no launch state given.
*/

import QtQuick
import QtTest

TestCase {
    id: testCase
    name: "HiddenAppsViews"
    width: 400
    height: 400
    when: windowShown

    function load(path) {
        var c = Qt.createComponent(path)
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        var view = createTemporaryObject(c, testCase, { launchState: null })
        verify(view)
        return view
    }

    function test_prefixView() {
        load("../../package/contents/ui/prefix/PrefixHiddenView.qml")
    }

    function test_settingsPage() {
        load("../../package/contents/ui/config/ConfigHiddenAppsContent.qml")
    }
}
