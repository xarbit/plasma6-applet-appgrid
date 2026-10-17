/*
    SPDX-FileCopyrightText: 2026 AppGrid Contributors
    SPDX-License-Identifier: GPL-2.0-or-later

    Coverage for FolderContextMenu.qml and RunnerContextMenu.qml: their rows
    (the folder menu's shared rows before each caller's own), and the
    requests their items send.
*/

import QtQuick
import QtTest

import "../../package/contents/ui/widgets"

TestCase {
    id: testCase
    name: "ContextMenus"
    width: 400
    height: 400
    when: windowShown

    SignalSpy { id: openSpy; signalName: "openRequested" }
    SignalSpy { id: favSpy; signalName: "favoriteToggled" }
    SignalSpy { id: actionSpy; signalName: "actionTriggered" }

    function load(file, props) {
        var c = Qt.createComponent("../../package/contents/ui/widgets/" + file)
        verify(c.status === Component.Ready, "load error: " + c.errorString())
        return createTemporaryObject(c, testCase, props)
    }

    function itemWithText(menu, text) {
        for (var i = 0; i < menu.count; ++i) {
            if (menu.itemAt(i).text === text)
                return menu.itemAt(i)
        }
        fail("no menu item " + text)
    }

    Component {
        id: extendedFolderMenu
        FolderContextMenu {
            AppGridMenuItem { text: "Extra" }
        }
    }

    function test_folderMenuSharedRowsThenTheCallers() {
        var m = createTemporaryObject(extendedFolderMenu, testCase)
        openSpy.target = m
        openSpy.clear()
        m.showFor("f1")
        compare(m.folderId, "f1")
        compare(m.count, 3)
        compare(m.itemAt(0).text, "Open Folder")
        compare(m.itemAt(1).text, "Launch All")
        compare(m.itemAt(2).text, "Extra")
        m.itemAt(0).clicked()
        compare(openSpy.count, 1)
        compare(openSpy.signalArguments[0][0], "f1")
    }

    function test_launchAllFollowsCanLaunchAll() {
        var m = load("FolderContextMenu.qml", { canLaunchAll: false })
        m.showFor("f1")
        verify(!m.itemAt(1).enabled)
        m.canLaunchAll = true
        verify(m.itemAt(1).enabled)
        m.close()
    }

    function test_runnerMenuFavouriteAndActions() {
        var m = load("RunnerContextMenu.qml", {})
        favSpy.target = m; actionSpy.target = m
        favSpy.clear(); actionSpy.clear()
        m.showFor(3, [{ text: "Copy", icon: "edit-copy" }], "applications:org.kde.kcalc.desktop", false)
        compare(m.sourceIndex, 3)
        compare(m.isFavorite, false)
        // The favourite row, the separator, then the action.
        tryCompare(m, "count", 3)
        compare(m.itemAt(0).text, "Add to Favorites")
        compare(m.itemAt(2).text, "Copy")
        itemWithText(m, "Add to Favorites").clicked()
        compare(favSpy.signalArguments[0][0], "applications:org.kde.kcalc.desktop")

        m.showFor(3, [{ text: "Copy", icon: "edit-copy" }], "applications:org.kde.kcalc.desktop", false)
        itemWithText(m, "Copy").clicked()
        compare(actionSpy.count, 1)
        compare(actionSpy.signalArguments[0][0], 3)
        compare(actionSpy.signalArguments[0][1], 0)
    }
}
